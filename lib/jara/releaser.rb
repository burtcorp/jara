# encoding: utf-8

require 'tmpdir'
require 'fileutils'
require 'pathname'
require 'puck'
require 'digest/md5'
require 'aws-sdk-core'
require 'socket'


module Jara
  ExecError = Class.new(JaraError)

  class Releaser
    def initialize(environment, bucket_name, options={})
      @environment = environment
      @bucket_name = bucket_name
      @shell = options[:shell] || Shell.new
      @archiver = options[:archiver] || Archiver.new
      @file_system = options[:file_system] || FileUtils
      @s3 = options[:s3]
      @branch = @environment == 'production' ? 'master' : @environment
    end

    def build_artifact
      if (artifact_path = find_artifact)
        artifact_path
      else
        date_stamp = Time.now.utc.strftime('%Y%m%d%H%M%S')
        destination_dir = File.join(project_dir, 'build', @environment)
        jar_name = [app_name, @environment, date_stamp, branch_sha[0, 8]].join('-') << '.jar'
        Dir.mktmpdir do |path|
          Dir.chdir(path) do
            @shell.exec('git clone %s . && git checkout %s' % [project_dir, branch_sha])
            @archiver.create(jar_name: jar_name)
            @file_system.mkdir_p(destination_dir)
            @file_system.cp("build/#{jar_name}", destination_dir)
          end
        end
        File.join(destination_dir, jar_name)
      end
    end

    def release
      return if already_released?
      local_path = find_artifact || build_artifact
      upload_artifact(local_path)
    end

    private

    JAR_CONTENT_TYPE = 'application/java-archive'

    def s3
      @s3 ||= Aws.s3
    end

    def app_name
      File.basename(project_dir)
    end

    def project_dir
      unless defined? @project_dir
        Pathname.new(Dir.getwd).descend do |path|
          if Dir.entries(path).include?('.git')
            @project_dir = path
            break
          end
        end
        unless defined? @project_dir
          raise JaraError, 'Could not find project directory'
        end
      end
      @project_dir
    end

    def branch_sha
      @branch_sha ||= begin
        result = @shell.exec('git rev-parse %s && git rev-parse origin/%s' % [@branch, @branch])
        local_sha, remote_sha = result.split("\n").take(2)
        if local_sha == remote_sha
          local_sha
        else
          raise JaraError, '%s and origin/%s are not in sync, did you forget to push?' % [@branch, @branch]
        end
      end
    end

    def metadata
      {
        'packaged_by' => "#{ENV['USER']}@#{Socket.gethostname}",
        'sha' => branch_sha
      }
    end

    def find_artifact
      candidates = Dir[File.join(project_dir, 'build', @environment, '*.jar')]
      candidates.select! { |path| path.include?(branch_sha[0, 8]) }
      candidates.sort.last
    end

    def upload_artifact(local_path)
      begin
        remote_path = [@environment, app_name, File.basename(local_path)].join('/')
        content_md5 = Digest::MD5.file(local_path).hexdigest
        File.open(local_path, 'rb') do |io|
          s3.put_object(
            bucket: @bucket_name,
            key: remote_path,
            content_type: JAR_CONTENT_TYPE,
            content_md5: content_md5,
            metadata: metadata,
            body: io,
          )
        end
      end
    end

    def already_released?
      listing = s3.list_objects(bucket: @bucket_name, prefix: [@environment, app_name, "#{app_name}-#{@environment}-"].join('/'))
      listing.contents.any? { |obj| obj.key.include?(branch_sha[0, 8]) }
    end

    class Shell
      def exec(command)
        output = %x(#{command})
        unless $?.success?
          raise ExecError, %(Command `#{command}` failed with output: #{output})
        end
        output
      end
    end

    class Archiver
      def create(options)
        Puck::Jar.new(options).create!
      end
    end
  end
end

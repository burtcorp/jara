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
      @re_release = options.fetch(:re_release, false)
      @extra_metadata = options[:metadata] || {}
      @shell = options[:shell] || Shell.new
      @archiver = options[:archiver] || Archiver.new
      @file_system = options[:file_system] || FileUtils
      @s3 = options[:s3]
      @logger = options[:logger] || IoLogger.new($stderr)
      @branch = @environment == 'production' ? 'master' : @environment
    end

    def build_artifact
      if @environment.nil?
        jar_name = "#{app_name}.jar"
        Dir.chdir(project_dir) do
          @archiver.create(jar_name: jar_name)
        end
        @logger.info('Created test artifact')
        File.join(project_dir, 'build', jar_name)
      elsif (artifact_path = find_local_artifact)
        @logger.warn('An artifact for %s already exists: %s' % [branch_sha[0, 8], File.basename(artifact_path)])
        artifact_path
      else
        date_stamp = Time.now.utc.strftime('%Y%m%d%H%M%S')
        destination_dir = File.join(project_dir, 'build', @environment)
        jar_name = [app_name, @environment, date_stamp, branch_sha[0, 8]].join('-') << '.jar'
        Dir.mktmpdir do |path|
          @shell.exec('git archive --format=tar --prefix=%s/ %s | (cd %s/ && tar xf -)' % [File.basename(path), branch_sha, File.dirname(path)])
          Dir.chdir(path) do
            @logger.info('Checked out %s from branch %s' % [branch_sha[0, 8], @branch])
            @archiver.create(jar_name: jar_name)
            @file_system.mkdir_p(destination_dir)
            @file_system.cp("build/#{jar_name}", destination_dir)
            @logger.info('Created artifact %s' % jar_name)
          end
        end
        File.join(destination_dir, jar_name)
      end
    end

    def release
      raise JaraError, 'No environment set' unless @environment
      raise JaraError, 'No bucket name set' unless @bucket_name
      if !@re_release && (obj = find_remote_artifact)
        @logger.warn('An artifact for %s already exists: s3://%s/%s' % [branch_sha[0, 8], @bucket_name, obj.key])
      else
        local_path = find_local_artifact || build_artifact
        upload_artifact(local_path)
      end
    end

    private

    JAR_CONTENT_TYPE = 'application/java-archive'

    def s3
      @s3 ||= Aws::S3::Client.new
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

    def git_remote
      @git_remote ||= @shell.exec('git config --get remote.origin.url')
    end

    def jruby_version
      @jruby_version ||= begin
        jruby_jars_path = $LOAD_PATH.grep(/\/jruby-jars/).first
        jruby_jars_path && jruby_jars_path.scan(/\/jruby-jars-(.+)\//).flatten.first
      end
    end

    def metadata
      m = {
        'packaged_by' => "#{ENV['USER']}@#{Socket.gethostname}",
        'sha' => branch_sha,
        'remote' => git_remote,
        'jruby' => jruby_version,
      }
      m.merge!(@extra_metadata)
      m
    end

    def find_local_artifact
      candidates = Dir[File.join(project_dir, 'build', @environment, '*.jar')]
      candidates.select! { |path| path.include?(branch_sha[0, 8]) }
      candidates.sort.last
    end

    def upload_artifact(local_path)
      remote_path = [@environment, app_name, File.basename(local_path)].join('/')
      content_md5 = Digest::MD5.file(local_path).base64digest
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
      @logger.info('Artifact uploaded to s3://%s/%s' % [@bucket_name, remote_path])
    end

    def find_remote_artifact
      listing = s3.list_objects(bucket: @bucket_name, prefix: [@environment, app_name, "#{app_name}-#{@environment}-"].join('/'))
      listing.contents.find { |obj| obj.key.include?(branch_sha[0, 8]) }
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

  class IoLogger
    def initialize(io)
      @io = io
    end

    def info(msg)
      @io.puts(msg)
    end

    def warn(msg)
      @io.puts(msg)
    end
  end

  class NullLogger
    def info(*); end
    def warn(*); end
  end

  NULL_LOGGER = NullLogger.new
end

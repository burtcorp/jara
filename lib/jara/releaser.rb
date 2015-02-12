# encoding: utf-8

require 'tmpdir'
require 'fileutils'
require 'pathname'
require 'digest/md5'
require 'aws-sdk-core'
require 'socket'


module Jara
  ExecError = Class.new(JaraError)

  class Releaser
    def initialize(environment, bucket_name=nil, options={})
      @environment = environment
      @bucket_name = bucket_name
      @re_release = options.fetch(:re_release, false)
      @extra_metadata = options[:metadata] || {}
      @build_command = options[:build_command]
      @shell = options[:shell] || Shell.new
      @archiver = create_archiver(options[:archiver])
      @file_system = options[:file_system] || FileUtils
      @s3 = options[:s3]
      @logger = options[:logger] || IoLogger.new($stderr)
      @branch = @environment == 'production' ? 'master' : @environment
    end

    def build_artifact
      if @environment.nil?
        archive_name = "#{app_name}.#{@archiver.extension}"
        Dir.chdir(project_dir) do
          @archiver.create(archive_name: archive_name)
        end
        @logger.info('Created test artifact')
        File.join(project_dir, 'build', archive_name)
      elsif (artifact_path = find_local_artifact)
        @logger.warn('An artifact for %s already exists: %s' % [branch_sha[0, 8], File.basename(artifact_path)])
        artifact_path
      else
        date_stamp = Time.now.utc.strftime('%Y%m%d%H%M%S')
        destination_dir = File.join(project_dir, 'build', @environment)
        archive_name = [app_name, @environment, date_stamp, branch_sha[0, 8]].join('-') << '.' << @archiver.extension
        Dir.mktmpdir do |path|
          @shell.exec('git archive --format=tar --prefix=%s/ %s | (cd %s/ && tar xf -)' % [File.basename(path), branch_sha, File.dirname(path)])
          Dir.chdir(path) do
            @logger.info('Checked out %s from branch %s' % [branch_sha[0, 8], @branch])
            if @build_command
              if @build_command.respond_to?(:call)
                @logger.info('Running build command')
                @build_command.call
              else
                @logger.info('Running build command: %s' % @build_command)
                @shell.exec(@build_command)
              end
            end
            @archiver.create(archive_name: archive_name)
            @file_system.mkdir_p(destination_dir)
            @file_system.cp("build/#{archive_name}", destination_dir)
            @logger.info('Created artifact %s' % archive_name)
          end
        end
        File.join(destination_dir, archive_name)
      end
    end

    def release
      raise JaraError, 'No environment set' unless @environment
      raise JaraError, 'No bucket name set' unless @bucket_name
      if !@re_release && (obj = find_remote_artifact)
        s3_uri = 's3://%s/%s' % [@bucket_name, obj.key]
        @logger.warn('An artifact for %s already exists: %s' % [branch_sha[0, 8], s3_uri])
        s3_uri
      else
        local_path = find_local_artifact || build_artifact
        upload_artifact(local_path)
      end
    end

    private

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

    def metadata
      m = {
        'packaged_by' => "#{ENV['USER']}@#{Socket.gethostname}",
        'sha' => branch_sha,
        'remote' => git_remote,
      }
      m.merge!(@extra_metadata)
      m.merge!(@archiver.metadata)
      m
    end

    def find_local_artifact
      candidates = Dir[File.join(project_dir, 'build', @environment, "*.#{@archiver.extension}")]
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
          content_type: @archiver.content_type,
          content_md5: content_md5,
          metadata: metadata,
          body: io,
        )
      end
      s3_uri = 's3://%s/%s' % [@bucket_name, remote_path]
      @logger.info('Artifact uploaded to %s' % s3_uri)
      s3_uri
    end

    def find_remote_artifact
      listing = s3.list_objects(bucket: @bucket_name, prefix: [@environment, app_name, "#{app_name}-#{@environment}-"].join('/'))
      listing.contents.find { |obj| obj.key.include?(branch_sha[0, 8]) }
    end

    def create_archiver(archiver)
      case archiver
      when :puck, :jar
        PuckArchiver.new(@shell)
      when :tar, :tgz
        Tarchiver.new(@shell)
      when nil
        if defined? PuckArchiver
          create_archiver(:puck)
        else
          create_archiver(:tgz)
        end
      else
        archiver
      end
    end

    class Shell
      def exec(command)
        output = %x(#{command})
        unless $?.success?
          raise ExecError, %(Command `#{command}` failed with output: #{output})
        end
        output
      rescue Errno::ENOENT => e
        raise ExecError, %(Command `#{command}` failed: #{e.message})
      end
    end

    class Archiver
      def initialize(shell)
        @shell = shell
      end

      def create(options)
      end

      def extension
      end

      def content_type
      end

      def metadata
        {}
      end
    end

    class Tarchiver < Archiver
      def create(options)
        FileUtils.mkdir_p('build')
        entries = Dir['*']
        entries.delete('build')
        @shell.exec("tar czf build/#{options[:archive_name]} #{entries.join(' ')}")
      end

      def extension
        'tgz'
      end

      def content_type
        'application/x-gzip'
      end
    end

    if defined? JRUBY_VERSION
      begin
        require 'puck'

        class PuckArchiver < Archiver
          def create(options)
            options = options.dup
            options[:jar_name] = options.delete(:archive_name)
            Puck::Jar.new(options).create!
          end

          def extension
            'jar'
          end

          def content_type
            'application/java-archive'
          end

          def metadata
            jruby_jars_path = $LOAD_PATH.grep(/\/jruby-jars/).first
            jruby_version = jruby_jars_path && jruby_jars_path.scan(/\/jruby-jars-(.+)\//).flatten.first
            if jruby_version
              super.merge('jruby' => jruby_version)
            else
              super
            end
          end
        end
      rescue LoadError
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

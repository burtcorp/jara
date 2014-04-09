# encoding: utf-8

require 'tmpdir'
require 'fileutils'
require 'pathname'
require 'puck'


module Jara
  ExecError = Class.new(JaraError)

  class Releaser
    def initialize(environment, options={})
      @environment = environment
      @shell = options[:shell] || Shell.new
      @archiver = options[:archiver] || Archiver.new
      @file_system = options[:file_system] || FileUtils
      @branch = 'master'
    end

    def build_artifact
      sha = find_branch_sha
      project_dir = find_project_dir
      app_name = File.basename(project_dir)
      date_stamp = Time.now.utc.strftime('%Y%m%d%H%M%S')
      destination_dir = File.join(project_dir, 'build', @environment)
      jar_name = [app_name, @environment, date_stamp, sha[0, 8]].join('-') << '.jar'
      Dir.mktmpdir do |path|
        Dir.chdir(path) do
          @shell.exec('git clone %s . && git checkout %s' % [project_dir, sha])
          @archiver.create(jar_name: jar_name)
          @file_system.mkdir_p(destination_dir)
          @file_system.cp("build/#{jar_name}", destination_dir)
        end
      end
      File.join(destination_dir, jar_name)
    end

    private

    def find_project_dir
      Pathname.new(Dir.getwd).descend do |path|
        if Dir.entries(path).include?('.git')
          return path
        end
      end
      raise JaraError, 'Could not find project directory'
    end

    def find_branch_sha
      result = @shell.exec('git rev-parse %s && git rev-parse origin/%s' % [@branch, @branch])
      local_sha, remote_sha = result.split("\n").take(2)
      if local_sha == remote_sha
        local_sha
      else
        raise JaraError, '%s and origin/%s are not in sync, did you forget to push?' % [@branch, @branch]
      end
    end

    class Shell
      def exec(command)
        $stderr.puts(command)
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

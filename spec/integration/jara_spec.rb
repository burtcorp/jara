# encoding: utf-8

require 'spec_helper'

describe 'Jara' do
  def isolated_run(dir, *commands)
    options = {}
    options = commands.pop if commands.last.is_a?(Hash)
    shell = options[:rvm] ? 'rvm-shell $RUBY_VERSION@jara-test_project' : 'bash'
    Dir.chdir(dir) do
      Bundler.with_clean_env do
        if ((s = ENV['EXEC_DEBUG']) && s.downcase.start_with?('y'))
          outputs = commands.map do |command|
            $stderr.puts("        $ #{command}")
            output = %x|#{shell} -c '#{command}' 2>&1|
            output.each_line { |line| $stderr.puts("        > #{line}") }
            unless $?.success?
              fail %(Command `#{command}` failed with output: #{output})
            end
            output
          end
          outputs.join("\n")
        else
          command = %|#{shell} -c '#{commands.join(' && ')}' 2>&1|
          output = %x|#{command}|
          unless $?.success?
            fail %(Command `#{command}` failed with output: #{output})
          end
          output
        end
      end
    end
  end

  def copy_test_project(tmp_dir, name='test_project')
    FileUtils.cp_r(File.expand_path("../#{name}", __FILE__), "#{tmp_dir}/#{name}")
  end

  def rewrite_gemfile(tmp_dir, name='test_project')
    gemfile = File.read("#{tmp_dir}/#{name}/Gemfile")
    gemfile.gsub!(/^(\s*)gem 'jara'.+$/, "\\1gem 'jara', path: '#{File.expand_path('../../..', __FILE__)}'")
    File.open("#{tmp_dir}/#{name}/Gemfile", 'w') { |io| io.write(gemfile) }
  end

  def setup_git(project_dir)
    isolated_run(project_dir,
      'git init --bare ../repo.git',
      'git init',
      'git add . && git commit -m "Fist!"',
      'git remote add origin ../repo.git',
      'git push -u origin master'
    )
  end

  if defined? JRUBY_VERSION
    context 'when creating a self-contained JAR' do
      def run_package(project_dir, environment='production')
        isolated_run(project_dir, "bundle exec rake clean package:#{environment}", rvm: true)
      end

      before :all do
        tmp_dir = Dir.mktmpdir
        @test_project_dir = "#{tmp_dir}/test_project"
        copy_test_project(tmp_dir)
        rewrite_gemfile(tmp_dir)
        setup_git(@test_project_dir)
      end

      context 'the archive' do
        let :jar_path do
          File.expand_path(Dir["#{@test_project_dir}/build/production/test_project-*.jar"].first)
        end

        let :jar do
          Java::JavaUtilJar::JarFile.new(Java::JavaIo::File.new(jar_path))
        end

        let :jar_entries do
          jar.entries.to_a.map(&:name)
        end

        before :all do
          run_package(@test_project_dir)
        end

        it 'has a name that includes the SHA of the master branch' do
          sha = isolated_run(@test_project_dir, 'git rev-parse master').strip
          jar_path.should include(sha[0, 8])
        end

        it 'includes the project files' do
          jar_entries.should include('META-INF/app.home/lib/test_project.rb')
        end

        it 'includes the dependencies' do
          jar_entries.grep(%r{META-INF/gem.home/paint-[^/]+/lib/paint.rb}).should_not be_empty
        end

        it 'does not include dependencies from groups other than the default' do
          jar_entries.grep(/puck/).should be_empty
        end

        it 'includes JRuby' do
          jar_entries.should include('org/jruby/Ruby.class')
        end

        it 'can run the files in bin' do
          output = isolated_run(Dir.tmpdir, %|java -jar #{jar_path} check|)
          output.should include('Hello from check')
          output = isolated_run(Dir.tmpdir, %|java -jar #{jar_path} main|)
          output.should include("Hello from main \e[31m52\e[0m\n")
        end
      end

      context 'when the latest version has not been pushed' do
        it 'fails the build' do
          isolated_run(@test_project_dir, 'touch foobaz', 'git add foobaz', 'git commit -m "foobaz the fizzbuzz"')
          expect { run_package(@test_project_dir) }.to raise_error(%r{master and origin/master are not in sync})
        end
      end

      context 'when the branch is "staging"' do
        let :jar_path do
          File.expand_path(Dir["#{@test_project_dir}/build/staging/test_project-staging-*.jar"].first)
        end

        before :all do
          isolated_run(@test_project_dir, 'git checkout -b staging', 'echo "puts \"Hello staging\"" > bin/check', 'git add .', 'git commit -m "Change the check message"', 'git push -u origin staging')
          run_package(@test_project_dir, 'staging')
        end

        it 'includes the SHA of the staging branch in the artifact name' do
          sha = isolated_run(@test_project_dir, 'git rev-parse staging').strip
          jar_path.should include(sha[0, 8])
        end

        it 'uses the staging branch' do
          output = isolated_run(Dir.tmpdir, %|java -jar #{jar_path} check|)
          output.should include('Hello staging')
        end

        it 'uses the staging branch even when currently on another branch' do
          isolated_run(@test_project_dir, 'git checkout master')
          output = isolated_run(Dir.tmpdir, %|java -jar #{jar_path} check|)
          output.should include('Hello staging')
        end
      end

      context 'from the working directory' do
        let :jar_path do
          File.expand_path("#{@test_project_dir}/build/test_project.jar")
        end

        before :all do
          isolated_run(@test_project_dir, 'echo "puts \"Hello test\"" > bin/check')
          run_package(@test_project_dir, 'test')
        end

        it 'includes unstaged changes' do
          output = isolated_run(Dir.tmpdir, %|java -jar #{jar_path} check|)
          output.should include('Hello test')
        end
      end
    end
  end

  context 'when creating a tarball' do
    def run_package(project_dir, environment='production')
      command = "bundle exec #{File.expand_path('../../..', __FILE__)}/bin/jara"
      command << " --environment #{environment}" if environment
      command << ' --archiver tgz'
      isolated_run(project_dir, command, rvm: true)
    end

    before :all do
      tmp_dir = Dir.mktmpdir
      @test_project_dir = "#{tmp_dir}/another_test_project"
      copy_test_project(tmp_dir, 'another_test_project')
      rewrite_gemfile(tmp_dir, 'another_test_project')
      setup_git(@test_project_dir)
    end

    context 'the archive' do
      let :tar_path do
        File.expand_path(Dir["#{@test_project_dir}/build/production/another_test_project-*.tgz"].first)
      end

      let :tar_entries do
        isolated_run(@test_project_dir, "tar tf #{tar_path}")
      end

      before :all do
        run_package(@test_project_dir)
      end

      it 'has a name that includes the SHA of the master branch' do
        sha = isolated_run(@test_project_dir, 'git rev-parse master').strip
        tar_path.should include(sha[0, 8])
      end

      it 'includes the project files' do
        tar_entries.should include('index.html')
        tar_entries.should include('js/hello-world.js')
      end
    end

    context 'when the latest version has not been pushed' do
      it 'fails the build' do
        isolated_run(@test_project_dir, 'touch foobaz', 'git add foobaz', 'git commit -m "foobaz the fizzbuzz"')
        expect { run_package(@test_project_dir) }.to raise_error(%r{master and origin/master are not in sync})
      end
    end

    context 'when the branch is "staging"' do
      let :tar_path do
        File.expand_path(Dir["#{@test_project_dir}/build/staging/another_test_project-*.tgz"].first)
      end

      let :tar_entries do
        isolated_run(@test_project_dir, "tar tf #{tar_path}")
      end

      before :all do
        isolated_run(@test_project_dir,
          'git checkout -b staging',
          'mkdir -p bin',
          'echo "puts \"Hello staging\"" > bin/check',
          'git add .',
          'git commit -m "Change the check message"',
          'git push -u origin staging'
        )
        run_package(@test_project_dir, 'staging')
      end

      it 'includes the SHA of the staging branch in the artifact name' do
        sha = isolated_run(@test_project_dir, 'git rev-parse staging').strip
        tar_path.should include(sha[0, 8])
      end

      it 'uses the staging branch' do
        tar_entries.should include('bin/check')
      end

      it 'uses the staging branch even when currently on another branch' do
        isolated_run(@test_project_dir, 'git checkout master')
        tar_entries.should include('bin/check')
      end
    end

    context 'from the working directory' do
      let :tar_path do
        File.expand_path(Dir["#{@test_project_dir}/build/another_test_project.tgz"].first)
      end

      let :tar_entries do
        isolated_run(@test_project_dir, "tar tf #{tar_path}")
      end

      before :all do
        isolated_run(@test_project_dir, 'mkdir -p bin && echo "puts \"Hello test\"" > bin/check')
        run_package(@test_project_dir, nil)
      end

      it 'includes unstaged changes' do
        isolated_run(@test_project_dir, 'git checkout master')
        tar_entries.should include('bin/check')
      end
    end
  end
end

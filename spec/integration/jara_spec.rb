# encoding: utf-8

require 'spec_helper'


module JavaJar
  include_package 'java.util.jar'
end

module JavaLang
  include_package 'java.lang'
end

describe 'Jara' do
  def isolated_run(dir, *commands)
    Dir.chdir(dir) do
      Bundler.with_clean_env do
        if ((s = ENV['EXEC_DEBUG']) && s.downcase.start_with?('y'))
          outputs = commands.map do |command|
            $stderr.puts("        $ #{command}")
            output = %x|rvm-shell $RUBY_VERSION@jara-test_project -c '#{command}' 2>&1|
            output.each_line { |line| $stderr.puts("        > #{line}") }
            unless $?.success?
              fail %(Command `#{command}` failed with output: #{output})
            end
            output
          end
          outputs.join("\n")
        else
          command = %|rvm-shell $RUBY_VERSION@jara-test_project -c '#{commands.join(' && ')}' 2>&1|
          output = %x|#{command}|
          unless $?.success?
            fail %(Command `#{command}` failed with output: #{output})
          end
          output
        end
      end
    end
  end

  def copy_test_project(tmp_dir)
    FileUtils.cp_r(File.expand_path('../test_project', __FILE__), "#{tmp_dir}/test_project")
  end

  def rewrite_gemfile(tmp_dir)
    gemfile = File.read("#{tmp_dir}/test_project/Gemfile")
    gemfile.gsub!(/^gem 'jara'.+$/, "gem 'jara', path: '#{File.expand_path('../../..', __FILE__)}'")
    File.open("#{tmp_dir}/test_project/Gemfile", 'w') { |io| io.write(gemfile) }
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

  def run_package(project_dir, environment='production')
    isolated_run(project_dir, "bundle exec rake clean package:#{environment}")
  end

  before :all do
    tmp_dir = Dir.mktmpdir
    @test_project_dir = "#{tmp_dir}/test_project"
    copy_test_project(tmp_dir)
    rewrite_gemfile(tmp_dir)
    setup_git(@test_project_dir)
  end

  context 'packaging the project as a JAR file that' do
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

    it 'includes the project files' do
      jar_entries.should include('META-INF/app.home/lib/test_project.rb')
    end

    it 'includes the dependencies' do
      jar_entries.should include('META-INF/gem.home/paint-0.8.7/lib/paint.rb')
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

  context 'packaging the project when the latest version has not been pushed' do
    it 'fails the build' do
      isolated_run(@test_project_dir, 'touch foobaz', 'git add foobaz', 'git commit -m "foobaz the fizzbuzz"')
      expect { run_package(@test_project_dir) }.to raise_error(%r{master and origin/master are not in sync})
    end
  end

  context 'packaging the project for staging' do
    let :jar_path do
      File.expand_path(Dir["#{@test_project_dir}/build/staging/test_project-staging-*.jar"].first)
    end

    before :all do
      isolated_run(@test_project_dir, 'git checkout -b staging', 'echo "puts \"Hello staging\"" > bin/check', 'git add .', 'git commit -m "Change the check message"', 'git push -u origin staging')
      run_package(@test_project_dir, 'staging')
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
end

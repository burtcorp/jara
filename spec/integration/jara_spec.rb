# encoding: utf-8

require 'spec_helper'


module JavaJar
  include_package 'java.util.jar'
end

module JavaLang
  include_package 'java.lang'
end

describe 'Jara' do
  def isolated_run(dir, cmd)
    Dir.chdir(dir) do
      Bundler.with_clean_env do
        command = %|rvm-shell $RUBY_VERSION@jara-test_project -c '#{cmd}' 2>&1|
        output = %x|#{command}|
        unless $?.success?
          fail %(Command `#{command}` failed with output: #{output})
        end
        output
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
    command = (<<-END).lines.map(&:strip).join(' && ')
    git init --bare ../repo.git
    git init
    git add . && git commit -m 'fist!'
    git remote add origin ../repo.git
    git push -u origin master
    END
    isolated_run(project_dir, command)
  end

  def run_package(project_dir=Dir.getwd)
    isolated_run(project_dir, 'bundle exec rake clean package:production')
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
end

# encoding: utf-8

$: << File.expand_path('../lib', __FILE__)

require 'bundler/setup'


namespace :setup do
  task :test_projects do
    %w[test_project another_test_project].each do |name|
      Dir.chdir("spec/integration/#{name}") do
        command = (<<-END).lines.map(&:strip).join(' && ')
        rm -f Gemfile.lock
        rvm-shell $RUBY_VERSION -c 'rvm gemset create jara-#{name}'
        rvm-shell $RUBY_VERSION@jara-#{name} -c 'gem install bundler'
        rvm-shell $RUBY_VERSION@jara-#{name} -c 'bundle install --retry 3'
        END
        puts command
        Bundler.clean_system(command)
      end
    end
  end
end

task :setup => ['setup:test_projects']


require 'rspec/core/rake_task'

RSpec::Core::RakeTask.new(:spec) do |r|
  r.rspec_opts = '--tty'
end


require 'bundler'

namespace :gem do
  Bundler::GemHelper.install_tasks
end

desc 'Release a new gem version'
task :release => [:spec, 'gem:release']

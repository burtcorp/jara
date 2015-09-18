# encoding: utf-8

$: << File.expand_path('../lib', __FILE__)

require 'bundler/setup'

VENDOR_PATH = File.expand_path('../vendor', __FILE__)

namespace :setup do
  task :test_projects do
    %w[test_project another_test_project].each do |name|
      Dir.chdir("spec/integration/#{name}") do
        bundle_path = File.join(VENDOR_PATH, name)
        command = "bundle install --retry=3 --gemfile=Gemfile --path=#{bundle_path} --binstubs=.bundle/bin"
        puts command
        Bundler.clean_system(command)
        rm_f '.bundle/config'
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

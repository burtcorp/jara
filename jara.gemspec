# encoding: utf-8

$: << File.expand_path('../lib', __FILE__)

require 'jara/version'


Gem::Specification.new do |s|
  s.name          = 'jara'
  s.version       = Jara::VERSION.dup
  s.license       = 'BSD-3-Clause'
  s.authors       = ['Burt Platform Team']
  s.email         = ['theo@burtcorp.com']
  s.homepage      = 'http://github.com/burtcorp/jara'
  s.summary       = %q{Builds and publishes JAR artifacts}
  s.description   = %q{Build self-contained JAR artifacts and publish them to S3}

  s.files         = Dir['bin/*', 'lib/**/*.rb', 'README.md', 'LICENSE.txt', '.yardopts']
  s.require_paths = %w(lib)
  s.bindir        = 'bin'
  s.default_executable = s.name

  s.required_ruby_version = '>= 1.9.3'

  if defined? JRUBY_VERSION
    s.platform = 'java'
    s.add_runtime_dependency 'puck'
  else
    s.platform = Gem::Platform::RUBY
  end

  s.add_runtime_dependency 'aws-sdk-core'
end

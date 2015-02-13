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
  s.summary       = %q{Builds and publishes project artifacts}
  s.description   = %q{Jara is a tool for building artifacts from a Git
                       repository, and can make standalone Jar files for JRuby.
                       It will check out a clean copy of your code and name
                       the artifact from the commit it was built from.}

  s.files         = Dir['bin/*', 'lib/**/*.rb', 'README.md', 'LICENSE.txt', '.yardopts']
  s.require_paths = %w(lib)
  s.bindir        = 'bin'
  s.executables   = %w[jara]

  s.platform = Gem::Platform::RUBY
  s.required_ruby_version = '>= 1.9.3'

  s.add_runtime_dependency 'aws-sdk-core'
end

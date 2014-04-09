# encoding: utf-8

$: << File.expand_path('../lib', __FILE__)

require 'jara/version'


Gem::Specification.new do |s|
  s.name          = 'jara'
  s.version       = Jara::VERSION.dup
  s.authors       = ['Burt Platform Team']
  s.email         = ['theo@burtcorp.com']
  s.homepage      = 'http://github.com/burtcorp/jara'
  s.summary       = %q{}
  s.description   = %q{}

  s.files         = Dir['lib/**/*.rb', 'README.md', '.yardopts']
  s.require_paths = %w(lib)

  s.platform = 'java'
  s.required_ruby_version = '>= 1.9.3'

  s.add_dependency 'puck'
end

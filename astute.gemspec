$:.unshift File.expand_path('lib', File.dirname(__FILE__))
require 'astute/version'

Gem::Specification.new do |s|
  s.name = 'astute'
  s.version = Astute::VERSION

  s.summary = 'Orchestrator for OpenStack deployment'
  s.description = 'Deployment Orchestrator of Puppet via MCollective. Works as a library or from CLI.'
  s.authors = ['Mike Scherbakov']
  s.email   = ['mscherbakov@mirantis.com']

  s.add_dependency 'activesupport', '~> 4.1'
  s.add_dependency 'mcollective-client', '>= 2.4.1'
  s.add_dependency 'symboltable', '>= 1.0.2'
  s.add_dependency 'rest-client', '>= 1.6.7'

  # Astute as service
  s.add_dependency 'bunny', '>= 2.0'
  s.add_dependency 'raemon', '>= 0.3'

  s.add_development_dependency 'facter'
  s.add_development_dependency 'rake', '10.0.4'
  s.add_development_dependency 'rspec', '>= 3.4.0'
  s.add_development_dependency 'mocha', '0.13.3'
  s.add_development_dependency 'simplecov', '~> 0.7.1'
  s.add_development_dependency 'simplecov-rcov', '~> 0.2.3'

  s.files   = Dir.glob("{bin,lib,spec,examples}/**/*")
  s.executables = ['astuted']
  s.require_path = 'lib'
end


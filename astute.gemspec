$:.unshift File.expand_path('lib', File.dirname(__FILE__))
require 'astute/version'

Gem::Specification.new do |s|
  s.name = 'astute'
  s.version = Astute::VERSION

  s.summary = 'Orchestrator for OpenStack deployment'
  s.description = 'Deployment Orchestrator of Puppet via MCollective. Works as a library or from CLI.'
  s.authors = ['Mike Scherbakov']
  s.email   = ['mscherbakov@mirantis.com']

  s.add_dependency 'activesupport'
  s.add_dependency 'mcollective-client'
  s.add_dependency 'symboltable'
  s.add_dependency 'rest-client'
  s.add_dependency 'net-ssh-multi'

  # Astute as service
  s.add_dependency 'amqp'
  s.add_dependency 'raemon'

  s.add_development_dependency 'facter'
  s.add_development_dependency 'rake'
  s.add_development_dependency 'rspec'
  s.add_development_dependency 'mocha'
  s.add_development_dependency 'simplecov'
  s.add_development_dependency 'simplecov-rcov'

  s.files   = Dir.glob("{bin,lib,spec,examples}/**/*")
  s.executables = ['astuted']
  s.require_path = 'lib'
end


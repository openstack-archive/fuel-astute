require 'rspec/core/rake_task'

namespace :spec do
  RSpec::Core::RakeTask.new(:unit) do |t|
    t.rspec_opts =  "--color --format documentation"
    specfile = ENV['S'].to_s.strip.length > 0 ? "*#{ENV['S']}*" : '*'
    t.pattern = "spec/unit/**/#{specfile}_spec.rb"
  end
end

task :default => 'spec:unit'
task :spec => 'spec:unit'

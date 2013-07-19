require 'rspec/core/rake_task'

rspec_opts = "--color --format documentation"

RSpec::Core::RakeTask.new(:spec, 'spec:unit') do |t|
  #t.rspec_opts = "--color --format documentation"
end

namespace :spec do
  RSpec::Core::RakeTask.new(:unit) do |t|
    t.rspec_opts = rspec_opts
    t.pattern = Dir['spec/unit/**/*_spec.rb']
  end
  RSpec::Core::RakeTask.new(:integration) do |t|
    #t.rspec_opts = rspec_opts
    t.pattern = Dir['spec/integration/**/*_spec.rb']
  end
end

task :default => :spec
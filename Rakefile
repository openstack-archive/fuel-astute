require 'rspec/core/rake_task'

namespace :spec do
  def test_pattern(test_type)
    specfile = ENV['S'].to_s.strip.length > 0 ? "*#{ENV['S']}*" : '*'
    pattern = "spec/#{test_type}/**/#{specfile}_spec.rb"
    puts pattern

    Dir[pattern]
  end

  RSpec::Core::RakeTask.new(:unit) do |t|
    t.rspec_opts =  "--color --format documentation"
    t.pattern = test_pattern('unit')
  end
  RSpec::Core::RakeTask.new(:integration) do |t|
    t.pattern = test_pattern('integration')
  end
end

task :default => 'spec:unit'

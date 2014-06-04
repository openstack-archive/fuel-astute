require File.join(File.dirname(__FILE__), '../spec_helper')

describe Astute::Raid do
  include SpecHelpers

  it 'should call Astute::Raid' do
    Astute::Raid.any_instance
  end
end

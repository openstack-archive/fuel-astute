require File.join(File.dirname(__FILE__), '../spec_helper')

describe Astute::Raid do
  include SpecHelpers

  let(:ctx) do
    ctx = mock('context')
    ctx.stubs(:task_id)
    ctx.stubs(:reporter)
    ctx.stubs(:status).returns(1 => 'success', 2 => 'success')
    ctx
  end

  let(:raid){Astute::Raid.new(ctx, [{'node' => 1}], vendor, 'cli', [])}

  context 'lsi' do
    let(:vendor){'lsi'}
    it 'should call lsi if vendor lsi' do
      raid.expects(:lsi).once
      raid.exec
    end
  end
end

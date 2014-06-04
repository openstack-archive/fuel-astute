require File.join(File.dirname(__FILE__), '../spec_helper')


describe Astute::RaidVendors::Lsi do
  include SpecHelpers

  let(:ctx) do
    ctx = mock('context')
    ctx.stubs(:task_id)
    ctx.stubs(:reporter)
    ctx.stubs(:status).returns(1 => 'success')
    ctx
  end

  def make_nodes(*uids)
    uids.map do |uid|
      {
        'uid' => uid.to_s
      }
    end
  end

  let(:nodes){[{'uid'=>1}]}
  let(:interface){'api'}

  let(:command) do {
    'raid_name' => 'Test_VD',
    'raid_lvl' => '10', 'controller_id' => '1',
    'phys_devices' => [1,2,3],
    'options' => {},
    }
  end
    let(:lsi_raid){ Astute::RaidVendors::Lsi.new(ctx, nodes, interface, command)}

  it 'should be correct API url ' do
     lsi_raid.expects(:run_shell_command).with(regexp_matches  /http:\/\/127\.0\.0\.1:8080/).once
     lsi_raid.create
  end

  it 'should be nytrocli if cli used' do
    interface = 'cli'
    lsi_raid = Astute::RaidVendors::Lsi.new(ctx, nodes, interface, command)
     lsi_raid.expects(:run_shell_command).with(regexp_matches  /nytrocli/).once
     lsi_raid.create
  end
end

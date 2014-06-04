#    Copyright 2013 Mirantis, Inc.
#
#    Licensed under the Apache License, Version 2.0 (the "License"); you may
#    not use this file except in compliance with the License. You may obtain
#    a copy of the License at
#
#         http://www.apache.org/licenses/LICENSE-2.0
#
#    Unless required by applicable law or agreed to in writing, software
#    distributed under the License is distributed on an "AS IS" BASIS, WITHOUT
#    WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied. See the
#    License for the specific language governing permissions and limitations
#    under the License.

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

  let(:nodes){[{'uid'=>1}]}

  let(:command) do {
    'raid_name' => 'Test_VD',
    'eid' => '252',
    'raid_lvl' => '1', 'controller_id' => '1',
    'phys_devices' => [1,2,3],
    'virtual_device' => 1,
    'options' => {},
    }
  end

  let(:lsi_raid){ Astute::RaidVendors::Lsi.new(ctx, nodes, interface, command)}

  context 'api' do
    let(:interface) {'api'}

    it 'should be correct API url ' do
      lsi_raid.expects(:run_shell_command).with(all_of(includes('http://127.0.0.1:8080/v0.5/controllers'))).once
       lsi_raid.create
    end

    it 'should be valid create action' do
      lsi_raid.expects(:run_shell_command).with(all_of(includes('controllers/1/virtualdevices -d'))).once
       lsi_raid.create
    end

    it 'should be valid delete action' do
      lsi_raid.expects(:run_shell_command).with(all_of(includes('DELETE'), includes('controllers/1/virtualdevices/1'))).once
      lsi_raid.delete
    end

    it 'should be valid create cachecade action' do
      lsi_raid.expects(:run_shell_command).with(all_of(includes('controllers/1/virtualdevices/cachecade'))).once
      lsi_raid.create_cachecade
    end

    it 'should be valid delete cachecade action' do
      lsi_raid.expects(:run_shell_command).with(all_of(includes('DELETE'), includes('controllers/1/cachecade/1'))).once
      lsi_raid.delete_cachecade
    end

    it 'should be valid create nytrocache action' do
      lsi_raid.expects(:run_shell_command).with(all_of(includes('controllers/1/virtualdevices/nytrocache'))).once
      lsi_raid.create_nytrocache
    end

    it 'should be valid delete cachecade action' do
      lsi_raid.expects(:run_shell_command).with(all_of(includes('DELETE'), includes('controllers/1/nytrocache/1'))).once
      lsi_raid.delete_nytrocache
    end

    it 'should be valid enable ssd caching action' do
      lsi_raid.expects(:run_shell_command).with(all_of(includes('true'), includes('controllers/1/virtualdevices/1 -d'))).once
       lsi_raid.enable_ssd_caching
    end

    it 'should be valid disable ssd caching action' do
      lsi_raid.expects(:run_shell_command).with(all_of(includes('false'), includes('controllers/1/virtualdevices/1'))).once
      lsi_raid.disable_ssd_caching
    end

    it 'should be valid add hotspare action' do
      (1..3).each do |device|
        lsi_raid.expects(:run_shell_command).with(all_of(includes("controllers/1/physicaldevices/252/#{device}/hotspare -d"))).once
      end
       lsi_raid.add_hotspare
    end

    it 'should be valid delete hotspare action' do
      (1..3).each do |device|
        lsi_raid.expects(:run_shell_command).with(all_of(includes('DELETE'), includes("controllers/1/physicaldevices/252/#{device}/hotspare"))).once
      end
       lsi_raid.delete_hotspare
    end

    it 'should be valid create hotspare drive action' do
      lsi_raid.expects(:run_shell_command).with(all_of(includes('controllers/1/virtualdevices/warpdrive'))).once
       lsi_raid.create_nwd
    end
  end

  context 'cli' do
    let(:interface) {'cli'}
    it 'should be nytrocli if cli used' do
       lsi_raid.expects(:run_shell_command).with(regexp_matches(/nytrocli/)).once
       lsi_raid.create
    end

    it 'should be valid create action' do
      lsi_raid.expects(:run_shell_command).with(regexp_matches(/\/c1 add vd type=r1 drives=252:1,2,3 pdperarray=/)).once
      lsi_raid.create
    end

    it 'should be valid delete action' do
      lsi_raid.expects(:run_shell_command).with(regexp_matches(/\/c1\/v1 del force/)).once
      lsi_raid.delete
    end

    it 'should be valid cachecade action' do
      lsi_raid.expects(:run_shell_command).with(regexp_matches(/\/c1 add VD cachecade type=r1 drives=252:1,2,3 write_cache/)).once
      lsi_raid.create_cachecade
    end

    it 'should be valid delete cachecade action' do
      lsi_raid.expects(:run_shell_command).with(regexp_matches(/\/c1\/v1 del cc/)).once
      lsi_raid.delete_cachecade
    end

    it 'should be valid create nytrocache action' do
      lsi_raid.expects(:run_shell_command).with(regexp_matches(/\/c1 add VD nytrocache type=r1 drives=252:1,2,3/)).once
      lsi_raid.create_nytrocache
    end

    it 'should be valid delete nytrocache action' do
      lsi_raid.expects(:run_shell_command).with(regexp_matches(/\/c1\/v1 del nytrocache/)).once
      lsi_raid.delete_nytrocache
    end

    it 'should be valid enable_ssd_caching action' do
      lsi_raid.expects(:run_shell_command).with(regexp_matches(/\/c1\/v1 set ssdcaching=on/)).once
      lsi_raid.enable_ssd_caching
    end

    it 'should be valid enable_ssd_caching action' do
      lsi_raid.expects(:run_shell_command).with(regexp_matches(/\/c1\/v1 set ssdcaching=off/)).once
      lsi_raid.disable_ssd_caching
    end

    it 'should be valid create hotspare action' do
      lsi_raid.expects(:run_shell_command).with(regexp_matches(/\/c1\/e252\/s1,2,3 add hotsparedrive/)).once
      lsi_raid.add_hotspare
    end

    it 'should be valid delete hotspare action' do
      lsi_raid.expects(:run_shell_command).with(regexp_matches(/\/c1\/e252\/s1,2,3 delete hotsparedrive/)).once
      lsi_raid.delete_hotspare
    end

    it 'should be valid create nytro warp drive action' do
      lsi_raid.expects(:run_shell_command).with(regexp_matches(/\/c1\/sall start format/)).once
      lsi_raid.create_nwd
    end
  end
end

#    Copyright 2014 Mirantis, Inc.
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

describe Astute::CobblerManager do
  include SpecHelpers

  let(:data) do
    {
      "engine"=>{
        "url"=>"http://localhost/cobbler_api",
        "username"=>"cobbler",
        "password"=>"cobbler",
        "master_ip"=>"127.0.0.1",
      },
      "task_uuid"=>"a5c44b9a-285a-4a0c-ae65-2ed6b3d250f4",
      "nodes" => [
        {
          'uid' => '1',
          'profile' => 'centos-x86_64',
          "slave_name"=>"controller-1",
          "admin_ip" =>'1.2.3.5',
          'power_type' => 'ssh',
          'power_user' => 'root',
          'power_pass' => '/root/.ssh/bootstrap.rsa',
          'power-address' => '1.2.3.5',
          'hostname' => 'name.domain.tld',
          'name_servers' => '1.2.3.4 1.2.3.100',
          'name_servers_search' => 'some.domain.tld domain.tld',
          'netboot_enabled' => '1',
          'ks_meta' => {
            'repo_setup' => {
              'repos' => [
                {
                  "type" => "deb",
                  "name" => "repo1",
                  "uri" => "ip_address:port/patch",
                  "suite" => "param1",
                  "section" => "param2",
                  "priority" => 1001
                },
                {
                  "type" => "rpm",
                  "name" => "repo2",
                  "uri" => "ip_address:port/patch",
                  "priority" => 1
                }
              ]
            }
          },
          'interfaces' => {
            'eth0' => {
              'mac_address' => '00:00:00:00:00:00',
              'static' => '1',
              'netmask' => '255.255.255.0',
              'ip_address' => '1.2.3.5',
              'dns_name' => 'node.mirantis.net',
            },
            'eth1' => {
              'mac_address' => '00:00:00:00:00:01',
              'static' => '0',
              'netmask' => '255.255.255.0',
              'ip_address' => '1.2.3.6',
            }
          },
          'interfaces_extra' => {
            'eth0' => {
              'peerdns' => 'no',
              'onboot' => 'yes',
            },
            'eth1' => {
              'peerdns' => 'no',
              'onboot' => 'yes',
            }
          }
        }
      ]
    }
  end

  let(:reporter) do
    reporter = mock('reporter')
    reporter.stub_everything
    reporter
  end

  let(:engine) do
    cobbler = mock('cobbler')
    cobbler.stub_everything
    cobbler
  end

  before(:each) do
    Astute::Provision::Cobbler.stubs(:new).returns(engine)
  end

  let(:cobbler_manager) { Astute::CobblerManager.new(data['engine'], reporter) }

  describe '#add_nodes' do
    before(:each) do
      cobbler_manager.stubs(:sleep)
    end

    it 'should sync engine status after end' do
      engine.stubs(:item_from_hash)
      cobbler_manager.expects(:sync).once

      cobbler_manager.add_nodes(data['nodes'])
    end

  end #'add_nodes'

  describe '#edit_nodes' do
    before(:each) do
      cobbler_manager.stubs(:sleep)
    end

    it 'should edit nodes' do
      cobbler_manager.stubs(:sync)
      engine.expects(:item_from_hash).with(
        'system',
        'controller-1',
        {'profile' => Astute.config.bootstrap_profile},
        :item_preremove => false)

      cobbler_manager.edit_nodes(
        data['nodes'],
        {'profile' => Astute.config.bootstrap_profile}
      )
    end

    it 'should sync at the end of the call' do
      engine.stubs(:item_from_hash)
      cobbler_manager.expects(:sync)

      cobbler_manager.edit_nodes(
        data['nodes'],
        {'profile' => Astute.config.bootstrap_profile}
      )
    end

    it 'should sync after an error' do
      engine.stubs(:item_from_hash).raises(RuntimeError)
      cobbler_manager.expects(:sync)

      expect{ cobbler_manager.edit_nodes(
        data['nodes'],
        {'profile' => Astute.config.bootstrap_profile}
      )}.to raise_error(RuntimeError)
    end

  end #'edit_nodes'

  describe '#remove_nodes' do
    before(:each) do
      cobbler_manager.stubs(:sleep)
    end

    it 'should try to remove nodes using cobbler engine' do
      engine.stubs(:system_exists?).returns(true).then.returns(false)
      engine.expects(:remove_system).once
      engine.expects(:sync).once
      cobbler_manager.remove_nodes(data['nodes'])
    end
    it 'should try to remove nodes three times before giving up' do
      engine.stubs(:system_exists?).returns(true)
      engine.expects(:remove_system).times(3)
      engine.expects(:sync).once
      cobbler_manager.remove_nodes(data['nodes'])
    end
    it 'should not try to remove nodes if they do not exist' do
      engine.stubs(:system_exists?).returns(false)
      engine.expects(:remove_system).never
      engine.expects(:sync).once
      cobbler_manager.remove_nodes(data['nodes'])
    end
  end

  describe '#reboot_nodes' do
    before(:each) do
      cobbler_manager.stubs(:sleep)
    end

    it 'should reboot nodes' do
      engine.expects(:power_reboot)

      cobbler_manager.reboot_nodes(data['nodes'])
    end

    context 'splay' do
      around(:each) do |example|
        old_iops_value = Astute.config.iops
        old_splay_factor_value = Astute.config.splay_factor
        example.run
        Astute.config.iops = old_iops_value
        Astute.config.splay_factor = old_splay_factor_value
      end

      it 'should delay between nodes reboot' do
        engine.stubs(:power_reboot)

        cobbler_manager.expects(:calculate_splay_between_nodes).returns(5).once
        cobbler_manager.expects(:sleep).with(5).once

        cobbler_manager.reboot_nodes(data['nodes'])
      end

      it 'use formula (node + 1) / iops * splay_factor / node' do
        Astute.config.iops = 100
        Astute.config.splay_factor = 100

        engine.stubs(:power_reboot)
        cobbler_manager.expects(:sleep).with(2.0).once

        cobbler_manager.reboot_nodes(data['nodes'])
      end
    end #'splay'

  end #'reboot_nodes'

  describe '#netboot_nodes' do
    it 'should netboot nodes' do
      cobbler_manager.stubs(:sync)
      engine.expects(:netboot).with('controller-1', false)

      cobbler_manager.netboot_nodes(data['nodes'], false)
    end

    it 'should sync at the end of the call' do
      engine.stubs(:netboot)
      cobbler_manager.expects(:sync)

      cobbler_manager.netboot_nodes(data['nodes'], false)
    end

    it 'should sync after an error' do
      engine.stubs(:netboot).raises(RuntimeError)
      cobbler_manager.expects(:sync)

      expect{cobbler_manager.netboot_nodes(data['nodes'], false)}
        .to raise_error(RuntimeError)
    end
  end #'edit_nodes'

  describe '#get_existent_nodes' do
    it 'should return existent nodes' do
      engine.expects(:system_exists?).with('controller-1').returns(true)

      expect(cobbler_manager.get_existent_nodes(data['nodes']))
        .to eql(data['nodes'])
    end

    it 'should not return non existent nodes' do
      engine.expects(:system_exists?).with('controller-1').returns(false)

      expect(cobbler_manager.get_existent_nodes(data['nodes']))
        .to eql([])
    end
  end #'get_existent_nodes'

  describe '#get_mac_duplicate_names' do
    it 'should return cobbler names of those systems that have at least one matching mac address' do
      engine.expects(:system_by_mac).with('00:00:00:00:00:00').returns({'name' => 'node-XXX'})
      engine.expects(:system_by_mac).with('00:00:00:00:00:01').returns(nil)

      expect(cobbler_manager.get_mac_duplicate_names(data['nodes']))
        .to eql(['node-XXX'])
    end

    it 'should return uniq list of cobbler names of those systems that have matching mac addresses' do
      engine.expects(:system_by_mac).with('00:00:00:00:00:00').returns({'name' => 'node-XXX'})
      engine.expects(:system_by_mac).with('00:00:00:00:00:01').returns({'name' => 'node-XXX'})

      expect(cobbler_manager.get_mac_duplicate_names(data['nodes']))
        .to eql(['node-XXX'])
    end

    it 'should not return nodes that have not matching mac addresses' do
      engine.expects(:system_by_mac).with('00:00:00:00:00:00').returns(nil)
      engine.expects(:system_by_mac).with('00:00:00:00:00:01').returns(nil)

      expect(cobbler_manager.get_mac_duplicate_names(data['nodes']))
        .to eql([])
    end
  end #'get_existent_nodes'

end

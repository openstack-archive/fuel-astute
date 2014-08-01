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
        "provision_method"=>"cobbler",
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
            'repo_metadata'=>{
              'repo1' => 'ip_address:port/patch param1 param2',
              'repo2' => 'ip_address:port/patch'
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

  describe '#add_nodes' do

    let(:engine) do
      cobbler = mock('cobbler')
      cobbler.stub_everything
      cobbler
    end

    before(:each) do
      Astute::Provision::Cobbler.stubs(:new).returns(engine)
    end

    let(:cobbler_manager) { Astute::CobblerManager.new(data['engine'], reporter) }

    it 'should convert data about additional repositories to easy parsing format' do
      cobbler_manager.stubs(:sync)

      engine.expects(:item_from_hash).with(
        'system',
        data['nodes'][0]['slave_name'],
        has_entry("ks_meta" => {
          "repo_metadata" =>
            "repo1=\"ip_address:port/patch param1 param2\",repo2=\"ip_address:port/patch\""
        }),
        {:item_preremove => true}
      ).once

      cobbler_manager.add_nodes(data['nodes'])
    end

    it 'should sync engine status after end' do
      cobbler_manager.stubs(:item_from_hash)
      cobbler_manager.expects(:sync).once

      cobbler_manager.add_nodes(data['nodes'])
    end

  end #'add_nodes'
end
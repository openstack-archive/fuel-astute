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

describe Astute::Orchestrator do
  include SpecHelpers

  before(:each) do
    @orchestrator = Astute::Orchestrator.new
    @reporter = mock('reporter')
    @reporter.stub_everything
  end

  describe '#verify_networks' do
    it 'should validate nodes availability before check' do
      nodes = [{'uid' => '1'}, {'uid' => '2'}]
      @orchestrator.expects(:node_type).returns([
        {'uid' => '1', 'node_type' => 'target'},
        {'uid' => '2', 'node_type' => 'bootstrap'}
      ])
      Astute::Network.expects(:check_network).once
      @orchestrator.verify_networks(@reporter, 'task_id', nodes)
    end

    it 'should raise error if nodes availability test failed' do
      nodes = [{'uid' => '1'}, {'uid' => '2'}]
      @orchestrator.expects(:node_type).returns([{'uid' => '1', 'node_type' => 'target'}])
      Astute::Network.expects(:check_network).never
      expect {@orchestrator.verify_networks(@reporter, 'task_id', nodes) }
        .to raise_error(/Network verification not avaliable because/)
    end

    it 'should check network configuration' do
      nodes = [{'uid' => '1'}]
      @orchestrator.stubs(:validate_nodes_access)
      Astute::Network.expects(:check_network).with(instance_of(Astute::Context), nodes)
      @orchestrator.verify_networks(@reporter, 'task_id', nodes)
    end
  end

  describe '#deploy' do
    it "calls with valid arguments without nailgun hooks" do
      nodes = [{'uid' => 1, 'role' => 'controller'}]
      Astute::DeploymentEngine::NailyFact.any_instance.expects(:deploy).
                                                       with(nodes, [], [])
      @orchestrator.deploy(@reporter, 'task_uuid', nodes)
    end

    it "calls with valid arguments including nailgun hooks" do
      nodes = [{'uid' => 1, 'role' => 'controller'}]
      pre_deployment = [{'type' => 'upload_file', 'uids' =>['1', '2', '3' ]}]
      post_deployment = [{'type' => 'sync', 'uids' =>['3', '2', '1' ]}]
      Astute::DeploymentEngine::NailyFact.any_instance.expects(:deploy).
                                                       with(nodes, pre_deployment, post_deployment)
      @orchestrator.deploy(@reporter, 'task_uuid', nodes, pre_deployment, post_deployment)
    end

    it "deploy method raises error if nodes list is empty" do
      expect {@orchestrator.deploy(@reporter, 'task_uuid', [])}.
                            to raise_error(/Deployment info are not provided!/)
    end
  end

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
          'ks_meta' => 'some_param=1 another_param=2',
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

end

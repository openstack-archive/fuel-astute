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

  describe '#execute_tasks' do
    it 'should execute tasks using nailgun hooks' do
      @orchestrator.stubs(:report_result)
      Astute::NailgunHooks.any_instance.expects(:process)

      @orchestrator.execute_tasks(@reporter, task_id="", tasks=[])
    end

    it 'should report succeed if all done without critical error' do
      Astute::NailgunHooks.any_instance.stubs(:process)
      @orchestrator.expects(:report_result).with({}, @reporter)

      @orchestrator.execute_tasks(@reporter, task_id="", tasks=[])
    end

    it 'it should rescue exception if task failed' do
      Astute::NailgunHooks.any_instance.stubs(:process)
        .raises(Astute::DeploymentEngineError)

      expect {@orchestrator.execute_tasks(@reporter, task_id="", tasks=[])}
        .to raise_error(Astute::DeploymentEngineError)
    end

  end #execute_tasks

  context 'stop deployment' do
    let(:data) do
      {
        "engine"=>{
          "url"=>"http://10.109.0.2:80/cobbler_api",
          "username"=>"cobbler",
          "password"=>"JTcu4VoM",
          "master_ip"=>"10.109.0.2"
        },
        "nodes"=>[],
        "stop_task_uuid"=>"26a5cfb5-797d-4385-9262-da88ae7a0e14",
        "task_uuid"=>"3958fe00-5969-44e2-bb21-413993cfbd6b"
      }
    end

    let(:nodes) { [{'uid' => '1'}, {'uid' => '2'}] }

    let(:mclient) do
      mclient = mock_rpcclient(nodes)
      Astute::MClient.any_instance.stubs(:rpcclient).returns(mclient)
      Astute::MClient.any_instance.stubs(:log_result).returns(mclient)
      Astute::MClient.any_instance.stubs(:check_results_with_retries).returns(mclient)
      mclient
    end

    describe '#stop_puppet_deploy' do

      it 'should do nothing if nodes list is empty' do
        result = @orchestrator.stop_puppet_deploy(@reporter, 'task_id', data['nodes'])
        expect(result).to eql(nil)
      end

      it 'should stop puppet' do
        mclient.expects(:stop_and_disable)
        @orchestrator.stop_puppet_deploy(@reporter, 'task_id', nodes)
      end
    end #stop_puppet_deploy

    describe '#remove_nodes' do

      it 'should do nothing if nodes list is empty' do
        expect(@orchestrator.remove_nodes(
          @reporter,
          'task_id',
          data['engine'],
          data['nodes'],
          options={}
        )).to eql(nil)
      end

      it 'should remove nodes' do
        Astute::Provisioner.any_instance.expects(:remove_nodes).once
        @orchestrator.expects(:perform_pre_deletion_tasks)
          .returns('status' => 'ready')

        @orchestrator.remove_nodes(
          @reporter,
          'task_id',
          data['engine'],
          nodes,
          options={}
        )
      end

      it 'should run pre deletion tasks' do
        Astute::Provisioner.any_instance.stubs(:remove_nodes)
        @orchestrator.expects(:perform_pre_deletion_tasks).with(
          @reporter,
          'task_id',
          nodes,
          {:reboot => true, :raise_if_error => false, :reset => false}
        ).returns('status' => 'ready')

        @orchestrator.remove_nodes(
          @reporter,
          'task_id',
          data['engine'],
          nodes,
          options={}
        )
      end

      it 'should deletion if run pre deletion tasks fail' do
        @orchestrator.expects(:perform_pre_deletion_tasks).with(
          @reporter,
          'task_id',
          nodes,
          {:reboot => true, :raise_if_error => false, :reset => true}
        ).returns('status' => 'error')

        Astute::Provisioner.any_instance.expects(:remove_nodes).never

        @orchestrator.remove_nodes(
          @reporter,
          'task_id',
          data['engine'],
          nodes,
          {:reboot => true, :raise_if_error => false, :reset => true}
        )
      end
    end

  end #stop deployment

  describe '#provision' do

    let(:provisioning_info) do
      {
        "engine"=>{
          "url"=>"http://localhost/cobbler_api",
          "username"=>"cobbler",
          "password"=>"cobbler",
          "master_ip"=>"127.0.0.1"
        },
        "pre_provision"=> [
          {
            "priority"=> 100,
            "type"=> "shell",
            "uids"=> ["master"],
            "parameters"=> {
              "retries"=> 1,
              "cmd"=> "fa_build_image--log-file/var/log/fuel-agent-env-1.log" \
                "--data_drivernailgun_build_image--input_data'",
              "cwd"=> "/",
              "timeout"=> 3600,
              "interval"=> 1
            }
            }
        ],
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
              'gw' => '10.20.0.2',
              'mco_enable' => 1,
              'mco_vhost' => 'mcollective'
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

    it 'should run provision' do
      Astute::CobblerManager.any_instance.stubs(:sleep)
      Astute::Provisioner.any_instance.stubs(:sleep)
      Astute::NailgunHooks.any_instance.stubs(:process)

      Astute::CobblerManager.any_instance.expects(:sync)
      Astute::Provisioner.any_instance.expects(:provision).with(
        instance_of(Astute::ProxyReporter::ProvisiningProxyReporter),
        'task_id',
        provisioning_info,
        'image'
      )

      @orchestrator.provision(
        @reporter,
        'task_id',
        provisioning_info,
        'image')
    end

    it 'should pre provision if pre provision tasks present' do
      Astute::CobblerManager.any_instance.stubs(:sleep)
      Astute::Provisioner.any_instance.stubs(:sleep)
      Astute::CobblerManager.any_instance.stubs(:sync)
      Astute::Provisioner.any_instance.stubs(:provision)

      Astute::NailgunHooks.any_instance.expects(:process)

      @orchestrator.provision(
        @reporter,
        'task_id',
        provisioning_info,
        'image')
    end

    it 'should not pre provision if no pre provision tasks present' do
      Astute::CobblerManager.any_instance.stubs(:sleep)
      Astute::Provisioner.any_instance.stubs(:sleep)
      Astute::CobblerManager.any_instance.stubs(:sync)
      Astute::Provisioner.any_instance.stubs(:provision)

      Astute::NailgunHooks.any_instance.expects(:process).never

      provisioning_info.delete('pre_provision')
      @orchestrator.provision(
        @reporter,
        'task_id',
        provisioning_info,
        'image')
    end

    it 'should raise informative error if pre provision tasks failed' do
      Astute::CobblerManager.any_instance.stubs(:sleep)
      Astute::Provisioner.any_instance.stubs(:sleep)
      Astute::CobblerManager.any_instance.stubs(:sync)
      Astute::Provisioner.any_instance.stubs(:provision)

      Astute::NailgunHooks.any_instance.expects(:process)
        .raises(Astute::DeploymentEngineError , "Failed to execute hook")

      expect{@orchestrator.provision(
        @reporter,
        'task_id',
        provisioning_info,
        'image')}.to raise_error(Astute::DeploymentEngineError,
          /Image build task failed/)
    end

  end #provision


end

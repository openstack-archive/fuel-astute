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
    def make_nodes(*uids)
      uids.map do |uid|
        {
          'uid' => uid.to_s,
          'networks' => [
            {
              'iface' => 'eth0',
              'vlans' => [100, 101]
            }
          ]
        }
      end
    end

    it "must be able to complete" do
      nodes = make_nodes(1, 2)
      res1 = {
        :data => {
          :uid => "1",
          :neighbours => {
            "eth0" => {
              "100" => {"1" => ["eth0"], "2" => ["eth0"]},
              "101" => {"1" => ["eth0"]}}}},
        :sender => "1"}
      res2 = {
        :data => {
          :uid => "2",
          :neighbours => {
            "eth0" => {
              "100" => {"1" => ["eth0"], "2" => ["eth0"]},
              "101" => {"1" => ["eth0"], "2" => ["eth0"]}
            }}},
        :sender => "2"}
      valid_res = {:statuscode => 0, :sender => '1'}
      mc_res1 = mock_mc_result(res1)
      mc_res2 = mock_mc_result(res2)
      mc_valid_res = mock_mc_result

      rpcclient = mock_rpcclient(nodes)

      rpcclient.expects(:get_probing_info).once.returns([mc_res1, mc_res2])
      nodes.each do |node|
        rpcclient.expects(:discover).with(:nodes => [node['uid']]).at_least_once

        data_to_send = {}
        node['networks'].each{ |net| data_to_send[net['iface']] = net['vlans'].join(",") }

        rpcclient.expects(:start_frame_listeners).
          with(:interfaces => data_to_send.to_json).
          returns([mc_valid_res]*2)

        rpcclient.expects(:send_probing_frames).
          with(:interfaces => data_to_send.to_json).
          returns([mc_valid_res]*2)
      end
      Astute::Network.expects(:check_dhcp)
      Astute::MClient.any_instance.stubs(:rpcclient).returns(rpcclient)

      res = @orchestrator.verify_networks(@reporter, 'task_uuid', nodes)
      expected = {"nodes" => [{"networks" => [{"iface"=>"eth0", "vlans"=>[100]}], "uid"=>"1"},
          {"networks"=>[{"iface"=>"eth0", "vlans"=>[100, 101]}], "uid"=>"2"}]}
      res.should eql(expected)
    end

    it "dhcp check should return expected info" do
      nodes = make_nodes(1, 2)
      expected_data = [{'iface'=>'eth1',
                        'mac'=> 'ff:fa:1f:er:ds:as'},
                       {'iface'=>'eth2',
                        'mac'=> 'ee:fa:1f:er:ds:as'}]
      json_output = JSON.dump(expected_data)
      res1 = {
        :data => {:out => json_output},
        :sender => "1"}
      res2 = {
        :data => {:out => json_output},
        :sender => "2"}

      rpcclient = mock_rpcclient(nodes)

      rpcclient.expects(:dhcp_discover).at_least_once.returns([res1, res2])

      rpcclient.discover(:nodes => ['1', '2'])
      res = Astute::Network.check_dhcp(rpcclient, nodes)

      expected = {"nodes" => [{:status=>"ready", :uid=>"1", :data=>expected_data},
                              {:status=>"ready", :uid=>"2", :data=>expected_data}],
                  "status"=> "ready"}
      res.should eql(expected)
    end

    it "returns error if nodes list is empty" do
      res = @orchestrator.verify_networks(@reporter, 'task_uuid', [])
      res.should eql({'status' => 'error', 'error' => "Network verification requires a minimum of two nodes."})
    end

    it "returns all vlans passed if only one node provided" do
      nodes = make_nodes(1)
      res = @orchestrator.verify_networks(@reporter, 'task_uuid', nodes)
      expected = {"nodes" => [{"uid"=>"1", "networks" => [{"iface"=>"eth0", "vlans"=>[100, 101]}]}]}
      res.should eql(expected)
    end
  end

  describe '#network_verifications_flow' do

    def make_nodes(*uids)
      uids.map do |uid|
        {
          'uid' => uid.to_s,
          'config' => {}
        }
      end
    end

    def format_nodes(nodes)
      formatted_nodes = {}
      nodes.each do |node|
        formatted_nodes[node['uid']] = node['config']
      end
      formatted_nodes
    end

    it "must run clean action if response from any agent was error" do
      nodes = make_nodes(1, 2)
      formatted_nodes = format_nodes(nodes)
      task = 'test'
      res1 = {
        :sender => "1",
        :status => 'error',
        :statuscode => 1}
      res2 = {
        :sender => "2",
        :status => 'inprogress'}

      rpcclient = mock_rpcclient(nodes)

      rpcclient.expects(:check).
        with(:data=>{'config'=>formatted_nodes, 'check'=>task, 'command'=>'start'}.to_json).
        once.
        returns([mock_mc_result(res1), mock_mc_result(res2)])

      rpcclient.expects(:check).
        with(:data=>{'config'=>formatted_nodes, 'check'=>task, 'command'=>'clean'}.to_json).
        once.
        returns([mock_mc_result]*2)

      Astute::MClient.any_instance.stubs(:rpcclient).returns(rpcclient)

      res = @orchestrator.network_verifications(@reporter, 'task_uuid', nodes, task)
      res['status'].should eql('error')
    end

    it "must stop running verifications flow if success response was received after any action" do
      nodes = make_nodes(1, 2)
      formatted_nodes = format_nodes(nodes)
      task = 'test'
      res1 = {
        :sender => "1",
        :status => 'success'}
      res2 = {
        :sender => "2",
        :status => 'success'}

      rpcclient = mock_rpcclient(nodes)

      rpcclient.expects(:check).
        with(:data=>{'config'=>formatted_nodes, 'check'=>task, 'command'=>'start'}.to_json).
        once.
        returns([mock_mc_result(res1), mock_mc_result(res2)])

      Astute::MClient.any_instance.stubs(:rpcclient).returns(rpcclient)

      res = @orchestrator.network_verifications(@reporter, 'task_uuid', nodes, task)
      res.should eql({'status' => 'success',
                      'progress' => 100,
                      "data" => {"1"=>{}, "2"=>{}}})
    end

    it "must successfully run action_start, action_send and action_get_info" do
      nodes = make_nodes(1, 2)
      formatted_nodes = format_nodes(nodes)
      task = 'test'
      res1 = {:sender => "1", :status => 'inpogress'}
      res2 = {:sender => "2", :status => 'inpogress'}

      rpcclient = mock_rpcclient(nodes)

      rpcclient.expects(:check).
        with(:data=>{'config'=>formatted_nodes, 'check'=>task, 'command'=>'start'}.to_json).
        once.
        returns([mock_mc_result({:sender => "1", :status => 'inpogress'}),
                 mock_mc_result({:sender => "2", :status => 'inpogress'})])

      rpcclient.expects(:check).
        with(:data=>{'config'=>formatted_nodes, 'check'=>task, 'command'=>'send'}.to_json).
        once.
        returns([mock_mc_result({:sender => "1", :status => 'inpogress'}),
                 mock_mc_result({:sender => "2", :status => 'inpogress'})])

      rpcclient.expects(:check).
        with(:data=>{'config'=>formatted_nodes, 'check'=>task, 'command'=>'get_info'}.to_json).
        once.
        returns([mock_mc_result({:sender => "1", :status => 'success'}),
                 mock_mc_result({:sender => "2", :status => 'success'})])

      Astute::MClient.any_instance.stubs(:rpcclient).returns(rpcclient)

      res = @orchestrator.network_verifications(@reporter, 'task_uuid', nodes, task)
      res.should eql({'status' => 'success',
                      'progress' => 100,
                      "data" => {"1"=>{}, "2"=>{}}})

    end

  end

  describe '#node_type' do
    it "must be able to return node type" do
      nodes = [{'uid' => '1'}]
      res = {:data => {:node_type => 'target'},
             :sender=>"1"}

      mc_res = mock_mc_result(res)
      mc_timeout = 5

      rpcclient = mock_rpcclient(nodes, mc_timeout)
      rpcclient.expects(:get_type).once.returns([mc_res])

      types = @orchestrator.node_type(@reporter, 'task_uuid', nodes, mc_timeout)
      types.should eql([{"node_type"=>"target", "uid"=>"1"}])
    end
  end

  describe '#remove_nodes' do

    let(:nodes) { [{'uid' => '1', 'slave_name' => ''}] }
    let(:engine_attrs) do
      {
        "url"=>"http://localhost/cobbler_api",
        "username"=>"cobbler",
        "password"=>"cobbler"
      }
    end

    before(:each) do
      remote = mock() do
        stubs(:call)
        stubs(:call).with('login', 'cobbler', 'cobbler').returns('remotetoken')
      end
      XMLRPC::Client = mock() do
        stubs(:new).returns(remote)
      end
    end

    it 'should use NodeRemover to remove nodes' do
      Astute::NodesRemover.any_instance.expects(:remove).once
      @orchestrator.remove_nodes(@reporter, task_id="task_id", engine_attrs, nodes, reboot=true)
    end

    context 'cobbler' do
      it 'should remove nodes from cobbler if node exist' do
        Astute::Provision::Cobbler.any_instance.stubs(:system_exists?).returns(true).twice
        Astute::NodesRemover.any_instance.stubs(:remove).once

        Astute::Provision::Cobbler.any_instance.expects(:remove_system).with(nodes.first['slave_name'])

        @orchestrator.remove_nodes(@reporter, task_id="task_id", engine_attrs, nodes, reboot=true)
      end

      it 'should not try to remove nodes from cobbler if node do not exist' do
        Astute::Provision::Cobbler.any_instance.stubs(:system_exists?).returns(false)
        Astute::NodesRemover.any_instance.stubs(:remove).once

        Astute::Provision::Cobbler.any_instance.expects(:remove_system).with(nodes.first['slave_name']).never

        @orchestrator.remove_nodes(@reporter, task_id="task_id", engine_attrs, nodes, reboot=true)
      end

      it 'should inform about nodes if remove operation fail' do
        Astute::Provision::Cobbler.any_instance.stubs(:system_exists?)
                                  .returns(true)
                                  .then.returns(true)
        Astute::NodesRemover.any_instance.stubs(:remove).once

        Astute::Provision::Cobbler.any_instance.expects(:remove_system).with(nodes.first['slave_name'])

        @orchestrator.remove_nodes(@reporter, task_id="task_id", engine_attrs, nodes, reboot=true)
      end

    end

  end

  describe '#deploy' do
    it "it calls deploy method with valid arguments" do
      nodes = [{'uid' => 1, 'role' => 'controller'}]
      Astute::DeploymentEngine::NailyFact.any_instance.expects(:deploy).
                                                       with(nodes)
      Astute::PostDeployActions.any_instance.expects(:process).returns(nil)
      @orchestrator.deploy(@reporter, 'task_uuid', nodes)
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
        "password"=>"cobbler"
      },
      "task_uuid"=>"a5c44b9a-285a-4a0c-ae65-2ed6b3d250f4",
      "nodes" => [
        {
          'uid' => '1',
          'profile' => 'centos-x86_64',
          "slave_name"=>"controller-1",
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

  describe '#provision' do

    context 'cobler cases' do
      it "raise error if cobler settings empty" do
        expect {@orchestrator.provision(@reporter, {}, data['nodes'])}.
                              to raise_error(/Settings for Cobbler must be set/)
      end
    end

    context 'node state cases' do
      before(:each) do
        remote = mock() do
          stubs(:call)
          stubs(:call).with('login', 'cobbler', 'cobbler').returns('remotetoken')
        end
        XMLRPC::Client = mock() do
          stubs(:new).returns(remote)
        end
        @orchestrator.stubs(:remove_nodes).returns([])
      end

      it "raises error if nodes list is empty" do
        expect {@orchestrator.provision(@reporter, data['engine'], {})}.
                              to raise_error(/Nodes to provision are not provided!/)
      end

      it "try to reboot nodes from list" do
        Astute::Provision::Cobbler.any_instance do
          expects(:power_reboot).with('controller-1')
        end
        Astute::CobblerManager.any_instance.stubs(:check_reboot_nodes).returns([])
        @orchestrator.provision(@reporter, data['engine'], data['nodes'])
      end

      before(:each) { Astute::Provision::Cobbler.any_instance.stubs(:power_reboot).returns(333) }

      context 'node reboot success' do
        before(:each) { Astute::Provision::Cobbler.any_instance.stubs(:event_status).
                                                   returns([Time.now.to_f, 'controller-1', 'complete'])}

        it "does not find failed nodes" do
          Astute::Provision::Cobbler.any_instance.stubs(:event_status).
                                                  returns([Time.now.to_f, 'controller-1', 'complete'])

          @orchestrator.provision(@reporter, data['engine'], data['nodes'])
        end

        it "sync engine state" do
          Astute::Provision::Cobbler.any_instance do
            expects(:sync).once
          end
          @orchestrator.provision(@reporter, data['engine'], data['nodes'])
        end

        it "should erase mbr for nodes" do
          @orchestrator.expects(:remove_nodes).with(@reporter, task_id="", data['engine'], data['nodes'], reboot=false).returns([])
          @orchestrator.provision(@reporter, data['engine'], data['nodes'])
        end
      end

      context 'node reboot fail' do
        before(:each) { Astute::Provision::Cobbler.any_instance.stubs(:event_status).
                                                                returns([Time.now.to_f, 'controller-1', 'failed'])}
        it "should sync engine state" do
          Astute::Provision::Cobbler.any_instance do
            expects(:sync).once
          end
          begin
            @orchestrator.provision(@reporter, data['engine'], data['nodes'])
          rescue
          end
        end

        it "raise error if failed node find" do
          expect do
            @orchestrator.provision(@reporter, data['engine'], data['nodes'])
          end.to raise_error(Astute::FailedToRebootNodesError)
        end
      end

    end
  end

  describe '#watch_provision_progress' do

    before(:each) do
      # Disable sleeping in test env (doubles the test speed)
      def @orchestrator.sleep_not_greater_than(time, &block)
        block.call
      end
    end

    it "raises error if nodes list is empty" do
      expect {@orchestrator.watch_provision_progress(@reporter, data['task_uuid'], {})}.
                            to raise_error(/Nodes to provision are not provided!/)
    end

    it "prepare provision log for parsing" do
      Astute::LogParser::ParseProvisionLogs.any_instance do
        expects(:prepare).with(data['nodes']).once
      end
      @orchestrator.stubs(:report_about_progress).returns()
      @orchestrator.stubs(:node_type).returns([{'uid' => '1', 'node_type' => 'target' }])

      @orchestrator.watch_provision_progress(@reporter, data['task_uuid'], data['nodes'])
    end

    it "ignore problem with parsing provision log" do
      Astute::LogParser::ParseProvisionLogs.any_instance do
        stubs(:prepare).with(data['nodes']).raises
      end

      @orchestrator.stubs(:report_about_progress).returns()
      @orchestrator.stubs(:node_type).returns([{'uid' => '1', 'node_type' => 'target' }])

      @orchestrator.watch_provision_progress(@reporter, data['task_uuid'], data['nodes'])
    end

    it 'provision nodes using mclient' do
      @orchestrator.stubs(:report_about_progress).returns()
      @orchestrator.expects(:node_type).returns([{'uid' => '1', 'node_type' => 'target' }])

      @orchestrator.watch_provision_progress(@reporter, data['task_uuid'], data['nodes'])
    end

    it "fail if timeout of provisioning is exceeded" do
      Astute::LogParser::ParseProvisionLogs.any_instance do
        stubs(:prepare).returns()
      end

      Timeout.stubs(:timeout).raises(Timeout::Error)

      msg = 'Timeout of provisioning is exceeded'

      error_msg = {
        'status' => 'error',
        'error' => msg,
        'progress' => 100,
        'nodes' => [{
            'uid' => '1',
            'status' => 'error',
            'error_msg' => msg,
            'progress' => 100,
            'error_type' => 'provision'}]}

      @reporter.expects(:report).with(error_msg).once
      @orchestrator.watch_provision_progress(@reporter, data['task_uuid'], data['nodes'])
    end

    it 'success report if all nodes were provisioned' do
      @orchestrator.stubs(:report_about_progress).returns()
      @orchestrator.expects(:node_type).returns([{'uid' => '1', 'node_type' => 'target' }])
      @orchestrator.stubs(:analize_node_types).returns([['1'], []])

      success_msg = {
        'status' => 'ready',
        'progress' => 100,
        'nodes' => [{
            'uid' => '1',
            'status' => 'provisioned',
            'progress' => 100}]}

      @reporter.expects(:report).with(success_msg).once
      @orchestrator.watch_provision_progress(@reporter, data['task_uuid'], data['nodes'])
    end

  end


  describe 'Red-hat checking' do
    let(:credentials) do
      {
        'release_name' => 'RELEASE_NAME',
        'redhat' => {
          'username' => 'user',
          'password' => 'password'
        }
      }
    end

    def mc_result(result)
      [mock_mc_result({:data => result})]
    end

    def stub_rpc(stdout='')
      mock_rpcclient.stubs(:execute).returns(mc_result(:exit_code => 0, :stdout => stdout, :stderr => ''))
    end

    describe '#check_redhat_credentials' do

      it 'should raise StopIteration in case of errors ' do
        stub_rpc("Before\nInvalid username or password\nAfter")

        expect do
          @orchestrator.check_redhat_credentials(@reporter, data['task_uuid'], credentials)
        end.to raise_error(StopIteration)
      end

      it 'should not raise errors' do
        stub_rpc
        @orchestrator.check_redhat_credentials(@reporter, data['task_uuid'], credentials)
      end
    end

    describe '#check_redhat_licenses' do
      it 'should raise StopIteration in case of errors ' do
        stub_rpc('{"openstack_licenses_physical_hosts_count":0}')

        expect do
          @orchestrator.check_redhat_licenses(@reporter, data['task_uuid'], credentials)
        end.to raise_error(StopIteration)
      end

      it 'should not raise errors ' do
        stub_rpc('{"openstack_licenses_physical_hosts_count":1}')
        @orchestrator.check_redhat_licenses(@reporter, data['task_uuid'], credentials)
      end
    end
  end

end

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
      rpcclient.expects(:dhcp_discover)
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
      Astute::MClient.any_instance.stubs(:rpcclient).returns(rpcclient)

      res = @orchestrator.verify_networks(@reporter, 'task_uuid', nodes)
      expected = {"nodes" => [{"networks" => [{"iface"=>"eth0", "vlans"=>[100]}], "uid"=>"1"},
          {"networks"=>[{"iface"=>"eth0", "vlans"=>[100, 101]}], "uid"=>"2"}]}
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

  it "in remove_nodes, it returns empty list if nodes are not provided" do
    res = @orchestrator.remove_nodes(@reporter, 'task_uuid', [])
    res.should eql({'nodes' => []})
  end

  it "remove_nodes cleans nodes and reboots them" do
    removed_hash = {:sender => '1',
                    :data => {:rebooted => true}}
    error_hash = {:sender => '2',
                  :data => {:rebooted => false, :error_msg => 'Could not reboot'}}
    nodes = [{'uid' => 1}, {'uid' => 2}]

    rpcclient = mock_rpcclient
    mc_removed_res = mock_mc_result(removed_hash)
    mc_error_res = mock_mc_result(error_hash)

    rpcclient.expects(:erase_node).at_least_once.with(:reboot => true).returns([mc_removed_res, mc_error_res])

    res = @orchestrator.remove_nodes(@reporter, 'task_uuid', nodes)
    res.should eql({'nodes' => [{'uid' => '1'}], 'status' => 'error',
                    'error_nodes' => [{"uid"=>"2", "error"=>"RPC method 'erase_node' failed "\
                                                            "with message: Could not reboot"}]})
  end

  it "it calls deploy method with valid arguments" do
    nodes = [{'uid' => 1}]
    attrs = {'a' => 'b'}
    Astute::DeploymentEngine::NailyFact.any_instance.expects(:deploy).
                                                     with([{'uid' => '1'}], attrs)
    @orchestrator.deploy(@reporter, 'task_uuid', nodes, attrs)
  end

  it "deploy method raises error if nodes list is empty" do
    expect {@orchestrator.deploy(@reporter, 'task_uuid', [], {})}.
                          to raise_error(/Nodes to deploy are not provided!/)
  end

  it "remove_nodes try to call MCAgent multiple times on error" do
    removed_hash = {:sender => '1',
                    :data => {:rebooted => true}}
    error_hash = {:sender => '2',
                  :data => {:rebooted => false, :error_msg => 'Could not reboot'}}
    nodes = [{'uid' => 1}, {'uid' => 2}]

    rpcclient = mock_rpcclient(nodes)
    mc_removed_res = mock_mc_result(removed_hash)
    mc_error_res = mock_mc_result(error_hash)

    retries = Astute.config[:MC_RETRIES]
    retries.should == 5
    rpcclient.expects(:discover).with(:nodes => ['2']).times(retries)
    rpcclient.expects(:erase_node).times(retries + 1).with(:reboot => true).returns([mc_removed_res, mc_error_res]).then.returns([mc_error_res])

    res = @orchestrator.remove_nodes(@reporter, 'task_uuid', nodes)
    res.should eql({'nodes' => [{'uid' => '1'}], 'status' => 'error',
                    'error_nodes' => [{"uid"=>"2", "error"=>"RPC method 'erase_node' failed "\
                                                            "with message: Could not reboot"}]})
  end

  it "remove_nodes try to call MCAgent multiple times on no response" do
    removed_hash = {:sender => '2', :data => {:rebooted => true}}
    then_removed_hash = {:sender => '3', :data => {:rebooted => true}}
    nodes = [{'uid' => 1}, {'uid' => 2}, {'uid' => 3}]

    rpcclient = mock_rpcclient(nodes)
    mc_removed_res = mock_mc_result(removed_hash)
    mc_then_removed_res = mock_mc_result(then_removed_hash)

    retries = Astute.config[:MC_RETRIES]
    rpcclient.expects(:discover).with(:nodes => %w(1 3)).times(1)
    rpcclient.expects(:discover).with(:nodes => %w(1)).times(retries - 1)
    rpcclient.expects(:erase_node).times(retries + 1).with(:reboot => true).
        returns([mc_removed_res]).then.returns([mc_then_removed_res]).then.returns([])

    res = @orchestrator.remove_nodes(@reporter, 'task_uuid', nodes)
    res['nodes'] = res['nodes'].sort_by{|n| n['uid'] }
    res.should eql({'nodes' => [{'uid' => '2'}, {'uid' => '3'}],
                    'inaccessible_nodes' => [{'uid'=>'1', 'error'=>'Node not answered by RPC.'}]})
  end

  it "remove_nodes and returns early if retries were successful" do
    removed_hash = {:sender => '1', :data => {:rebooted => true}}
    then_removed_hash = {:sender => '2', :data => {:rebooted => true}}
    nodes = [{'uid' => 1}, {'uid' => 2}]

    rpcclient = mock_rpcclient(nodes)
    mc_removed_res = mock_mc_result(removed_hash)
    mc_then_removed_res = mock_mc_result(then_removed_hash)

    retries = Astute.config[:MC_RETRIES]
    retries.should_not == 2
    rpcclient.expects(:discover).with(:nodes => %w(2)).times(1)
    rpcclient.expects(:erase_node).times(2).with(:reboot => true).
        returns([mc_removed_res]).then.returns([mc_then_removed_res])

    res = @orchestrator.remove_nodes(@reporter, 'task_uuid', nodes)
    res['nodes'] = res['nodes'].sort_by{|n| n['uid'] }
    res.should eql({'nodes' => [{'uid' => '1'}, {'uid' => '2'}]})
  end

  it "remove_nodes do not fail if any of nodes failed"

  before(:all) do
    @data = {
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
          "name"=>"controller-1",
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
    }.freeze
  end

  describe '#fast_provision' do

    context 'cobler cases' do
      it "raise error if cobler settings empty" do
        expect {@orchestrator.fast_provision(@reporter, {}, @data['nodes'])}.
                              to raise_error(StopIteration)
      end
    end

    context 'node state cases' do
      before(:each) do

        remote = mock() do
          stubs(:call)
          stubs(:call).with('login', 'cobbler', 'cobbler').returns('remotetoken')
        end
        @tmp = XMLRPC::Client
        XMLRPC::Client = mock() do
          stubs(:new).returns(remote)
        end
      end

      it "raises error if nodes list is empty" do
        expect {@orchestrator.fast_provision(@reporter, @data['engine'], {})}.
                              to raise_error(/Nodes to provision are not provided!/)
      end

      it "try to reboot nodes from list" do
        Astute::Provision::Cobbler.any_instance do
          expects(:power_reboot).with('controller-1')
        end
        @orchestrator.stubs(:check_reboot_nodes).returns([])
        @orchestrator.fast_provision(@reporter, @data['engine'], @data['nodes'])
      end

      before(:each) { Astute::Provision::Cobbler.any_instance.stubs(:power_reboot).returns(333) }

      context 'node reboot success' do

        before(:each) { Astute::Provision::Cobbler.any_instance.stubs(:event_status).
                                                   returns([Time.now.to_f, 'controller-1', 'complete'])}

        it "does not find failed nodes" do
          Astute::Provision::Cobbler.any_instance.stubs(:event_status).
                                                  returns([Time.now.to_f, 'controller-1', 'complete'])

          @orchestrator.fast_provision(@reporter, @data['engine'], @data['nodes'])
        end

        it "report about success" do
          @reporter.expects(:report).with({'status' => 'ready', 'progress' => 100}).returns(true)
          @orchestrator.fast_provision(@reporter, @data['engine'], @data['nodes'])
        end

        it "sync engine state" do
          Astute::Provision::Cobbler.any_instance do
            expects(:sync).once
          end
          @orchestrator.fast_provision(@reporter, @data['engine'], @data['nodes'])
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
            @orchestrator.fast_provision(@reporter, @data['engine'], @data['nodes'])
          rescue
          end
        end

        it "raise error if failed node find" do
          expect {@orchestrator.fast_provision(@reporter, @data['engine'], @data['nodes'])}.to raise_error(StopIteration)
        end

      end

    end
  end

  describe '#provision' do

    before(:each) do
      # Disable sleeping in test env (doubles the test speed)
      def @orchestrator.sleep_not_greater_than(time, &block)
        block.call
      end
    end

    it "raises error if nodes list is empty" do
      expect {@orchestrator.provision(@reporter, @data['task_uuid'], {})}.
                            to raise_error(/Nodes to provision are not provided!/)
    end

    it "prepare provision log for parsing" do
      Astute::LogParser::ParseProvisionLogs.any_instance do
        expects(:prepare).with(@data['nodes']).once
      end
      @orchestrator.stubs(:report_about_progress).returns()
      @orchestrator.stubs(:node_type).returns([{'uid' => '1', 'node_type' => 'target' }])

      @orchestrator.provision(@reporter, @data['task_uuid'], @data['nodes'])
    end

    it "ignore problem with parsing provision log" do
      Astute::LogParser::ParseProvisionLogs.any_instance do
        stubs(:prepare).with(@data['nodes']).raises
      end

      @orchestrator.stubs(:report_about_progress).returns()
      @orchestrator.stubs(:node_type).returns([{'uid' => '1', 'node_type' => 'target' }])

      @orchestrator.provision(@reporter, @data['task_uuid'], @data['nodes'])
    end

    it 'provision nodes using mclient' do
      @orchestrator.stubs(:report_about_progress).returns()
      @orchestrator.expects(:node_type).returns([{'uid' => '1', 'node_type' => 'target' }])

      @orchestrator.provision(@reporter, @data['task_uuid'], @data['nodes'])
    end

    it "fail if timeout of provisioning is exceeded" do
      Astute::LogParser::ParseProvisionLogs.any_instance do
        stubs(:prepare).returns()
      end

      Timeout.stubs(:timeout).raises(Timeout::Error)

      msg = 'Timeout of provisioning is exceeded.'
      error_mgs = {'status' => 'error', 'error' => msg, 'nodes' => [{ 'uid' => '1',
                                                            'status' => 'error',
                                                            'error_msg' => msg,
                                                            'progress' => 100,
                                                            'error_type' => 'provision'}]}

      @reporter.expects(:report).with(error_mgs).once
      @orchestrator.provision(@reporter, @data['task_uuid'], @data['nodes'])
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

      it 'Should raise StopIteration in case of errors ' do
        stub_rpc("Before\nInvalid username or password\nAfter")

        expect do
          @orchestrator.check_redhat_credentials(@reporter, @data['task_uuid'], credentials)
        end.to raise_error(StopIteration)
      end

      it 'Should not raise errors ' do
        stub_rpc
        @orchestrator.check_redhat_credentials(@reporter, @data['task_uuid'], credentials)
      end
    end

    describe '#check_redhat_licenses' do
      it 'Should raise StopIteration in case of errors ' do
        stub_rpc('{"openstack_licenses_physical_hosts_count":0}')

        expect do
          @orchestrator.check_redhat_licenses(@reporter, @data['task_uuid'], credentials)
        end.to raise_error(StopIteration)
      end

      it 'Should not raise errors ' do
        stub_rpc('{"openstack_licenses_physical_hosts_count":1}')
        @orchestrator.check_redhat_licenses(@reporter, @data['task_uuid'], credentials)
      end
    end
  end

end

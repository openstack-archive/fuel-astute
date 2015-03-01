#    Copyright 2015 Mirantis, Inc.
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

describe Astute::Provisioner do
  include SpecHelpers

  before(:each) do
    @provisioner = Astute::Provisioner.new
    @reporter = mock('reporter')
    @reporter.stub_everything
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

      types = @provisioner.node_type(@reporter, 'task_uuid', nodes.map { |n| n['uid'] }, mc_timeout)
      types.should eql([{"node_type"=>"target", "uid"=>"1"}])
    end
  end

  describe '#remove_nodes' do

    let(:nodes) { [{'uid' => '1', 'slave_name' => ''}] }
    let(:engine_attrs) do
      {
        "url"=>"http://localhost/cobbler_api",
        "username"=>"cobbler",
        "password"=>"cobbler",
        "master_ip"=>"127.0.0.1",
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
      Astute::NodesRemover.any_instance.expects(:remove).once.returns({})
      Astute::Rsyslogd.expects(:send_sighup).once
      @provisioner.remove_nodes(@reporter, task_id="task_id", engine_attrs, nodes, reboot=true)
    end

    it 'should return list of nodes which removed' do
      Astute::NodesRemover.any_instance.expects(:remove).once.returns({"nodes"=>[{"uid"=>"1"}]})
      Astute::Rsyslogd.stubs(:send_sighup).once
      expect(@provisioner.remove_nodes(
        @reporter,
        task_id="task_id",
        engine_attrs,
        nodes,
        reboot=true
      )).to eql({"nodes"=>[{"uid"=>"1"}]})
    end

    context 'if exception in case of error enable' do
      it 'should raise error if nodes removing operation via mcollective failed(error)' do
        Astute::NodesRemover.any_instance.expects(:remove).once.returns({
          'status' => 'error',
          'error_nodes' => [{"uid"=>"1"}]
        })
        Astute::Rsyslogd.stubs(:send_sighup).never
        expect {@provisioner.remove_nodes(
          @reporter,
          task_id="task_id",
          engine_attrs,
          nodes,
          reboot=true,
          raise_if_error=true
        )}.to raise_error(/Mcollective problem with nodes/)
      end

      it 'should raise error if nodes removing operation via mcollective failed(inaccessible)' do
        Astute::NodesRemover.any_instance.expects(:remove).once.returns({
          'inaccessible_nodes' => [{"uid"=>"1"}]
        })
        Astute::Rsyslogd.stubs(:send_sighup).never
        expect {@provisioner.remove_nodes(
          @reporter,
          task_id="task_id",
          engine_attrs,
          nodes,
          reboot=true,
          raise_if_error=true
        )}.to raise_error(/Mcollective problem with nodes/)
      end
    end  #exception

    context 'cobbler' do
      it 'should remove nodes from cobbler if node exist' do
        Astute::Provision::Cobbler.any_instance.stubs(:system_exists?).returns(true).twice
        Astute::NodesRemover.any_instance.stubs(:remove).once.returns({})
        Astute::Rsyslogd.expects(:send_sighup).once

        Astute::Provision::Cobbler.any_instance.expects(:remove_system).with(nodes.first['slave_name'])

        @provisioner.remove_nodes(@reporter, task_id="task_id", engine_attrs, nodes, reboot=true)
      end

      it 'should not try to remove nodes from cobbler if node do not exist' do
        Astute::Provision::Cobbler.any_instance.stubs(:system_exists?).returns(false)
        Astute::NodesRemover.any_instance.stubs(:remove).once.returns({})
        Astute::Rsyslogd.expects(:send_sighup).once

        Astute::Provision::Cobbler.any_instance.expects(:remove_system).with(nodes.first['slave_name']).never

        @provisioner.remove_nodes(@reporter, task_id="task_id", engine_attrs, nodes, reboot=true)
      end

      it 'should inform about nodes if remove operation fail' do
        Astute::Provision::Cobbler.any_instance.stubs(:system_exists?)
                                  .returns(true)
                                  .then.returns(true)
        Astute::NodesRemover.any_instance.stubs(:remove).once.returns({})
        Astute::Rsyslogd.expects(:send_sighup).once

        Astute::Provision::Cobbler.any_instance.expects(:remove_system).with(nodes.first['slave_name'])

        @provisioner.remove_nodes(@reporter, task_id="task_id", engine_attrs, nodes, reboot=true)
      end
    end #cobbler
  end #remove_nodes

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

  describe '#provision' do

    context 'cobler cases' do
      it "raise error if cobler settings empty" do
        @provisioner.stubs(:provision_and_watch_progress).returns(nil)
        expect {@provisioner.provision(@reporter, data['task_uuid'], {}, data['nodes'])}.
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
        @provisioner.stubs(:remove_nodes).returns([])
        Astute::CobblerManager.any_instance.stubs(:sleep)
      end

      before(:each) do
        @provisioner.stubs(:provision_and_watch_progress).returns(nil)
        @provisioner.stubs(:control_reboot_using_ssh).returns(nil)
      end

      it "raises error if nodes list is empty" do
        expect {@provisioner.provision(@reporter, data['task_uuid'], data['engine'], {})}.
                              to raise_error(/Nodes to provision are not provided!/)
      end

      it "try to reboot nodes from list" do
        Astute::Provision::Cobbler.any_instance do
          expects(:power_reboot).with('controller-1')
        end
        Astute::CobblerManager.any_instance.stubs(:check_reboot_nodes).returns([])

        @provisioner.provision(@reporter, data['task_uuid'], data['engine'], data['nodes'])
      end

      before(:each) { Astute::Provision::Cobbler.any_instance.stubs(:power_reboot).returns(333) }

      context 'node reboot success' do
        before(:each) { Astute::Provision::Cobbler.any_instance.stubs(:event_status).
                                                   returns([Time.now.to_f, 'controller-1', 'complete'])}

        it "does not find failed nodes" do
          Astute::Provision::Cobbler.any_instance.stubs(:event_status).
                                                  returns([Time.now.to_f, 'controller-1', 'complete'])

          @provisioner.provision(@reporter, data['task_uuid'], data['engine'], data['nodes'])
        end

        it "sync engine state" do
          Astute::Provision::Cobbler.any_instance do
            expects(:sync).once
          end
          @provisioner.provision(@reporter, data['task_uuid'], data['engine'], data['nodes'])
        end

        it "should erase mbr for nodes" do
          @provisioner.expects(:remove_nodes).with(
            @reporter,
            data['task_uuid'],
            data['engine'],
            data['nodes'],
            reboot=false,
            fail_if_error=true
          ).returns([])
          @provisioner.provision(@reporter, data['task_uuid'], data['engine'], data['nodes'])
        end

        it 'should not try to unlock node discovery' do
          @provisioner.expects(:unlock_nodes_discovery).never
          @provisioner.provision(@reporter, data['task_uuid'], data['engine'], data['nodes'])
        end

        it 'should try to reboot nodes using ssh(insurance for cobbler)' do
          @provisioner.expects(:control_reboot_using_ssh).with(@reporter, data['task_uuid'], data['nodes']).once
          @provisioner.provision_piece(@reporter, data['task_uuid'], data['engine'], data['nodes'])
        end
      end

      context 'node reboot fail' do
        before(:each) do
          Astute::Provision::Cobbler.any_instance
                                    .stubs(:event_status)
                                    .returns([Time.now.to_f, 'controller-1', 'failed'])
          @provisioner.stubs(:unlock_nodes_discovery)
        end
        it "should sync engine state" do
          Astute::Provision::Cobbler.any_instance do
            expects(:sync).once
          end
          begin
            @provisioner.stubs(:provision_and_watch_progress).returns(nil)
            @provisioner.provision(@reporter, data['task_uuid'], data['engine'], data['nodes'])
          rescue
          end
        end

        it "raise error if failed node find" do
          expect do
            @provisioner.stubs(:provision_and_watch_progress).returns(nil)
            @provisioner.provision_piece(@reporter, data['task_uuid'], data['engine'], data['nodes'])
          end.to raise_error(Astute::FailedToRebootNodesError)
        end

        it "should try to unlock nodes discovery" do
          @provisioner.expects(:unlock_nodes_discovery)
          begin
            @provisioner.provision_piece(@reporter, data['task_uuid'], data['engine'], data['nodes'])
          rescue
          end
        end

        it 'should not try to reboot nodes using ssh(insurance for cobbler)' do
          @provisioner.expects(:control_reboot_using_ssh).never
          begin
            @provisioner.provision(@reporter, data['task_uuid'], data['engine'], data['nodes'])
          rescue
          end
        end
      end

    end
  end

  describe '#provision_and_watch_progress' do

    before(:each) do
      # Disable sleeping in test env (doubles the test speed)
      def @provisioner.sleep_not_greater_than(time, &block)
        block.call
      end
    end

    it "raises error if nodes list is empty" do
      expect {@provisioner.provision_and_watch_progress(@reporter, data['task_uuid'], {}, data['engine'])}.
                            to raise_error(/Nodes to provision are not provided!/)
    end

    it "prepare provision log for parsing" do
      Astute::LogParser::ParseProvisionLogs.any_instance do
        expects(:prepare).with(data['nodes']).once
      end
      @provisioner.stubs(:provision_piece).returns(nil)
      @provisioner.stubs(:report_about_progress).returns()
      @provisioner.stubs(:node_type).returns([{'uid' => '1', 'node_type' => 'target' }])

      @provisioner.provision_and_watch_progress(@reporter, data['task_uuid'], data['nodes'], data['engine'])
    end

    it "ignore problem with parsing provision log" do
      Astute::LogParser::ParseProvisionLogs.any_instance do
        stubs(:prepare).with(data['nodes']).raises
      end

      @provisioner.stubs(:report_about_progress).returns()
      @provisioner.stubs(:provision_piece).returns(nil)
      @provisioner.stubs(:node_type).returns([{'uid' => '1', 'node_type' => 'target' }])

      @provisioner.provision_and_watch_progress(@reporter, data['task_uuid'], data['nodes'], data['engine'])
    end

    it 'provision nodes using mclient' do
      @provisioner.stubs(:report_about_progress).returns()
      @provisioner.stubs(:provision_piece).returns(nil)
      @provisioner.expects(:node_type).returns([{'uid' => '1', 'node_type' => 'target' }])

      @provisioner.provision_and_watch_progress(@reporter, data['task_uuid'], data['nodes'], data['engine'])
    end

    it "fail if timeout of provisioning is exceeded" do
      @provisioner.stubs(:report_about_progress).returns()
      Astute.config.provisioning_timeout = -5
      @provisioner.stubs(:node_type).returns([])
      @provisioner.stubs(:provision_piece).returns(nil)
      Astute::LogParser::ParseProvisionLogs.any_instance do
        stubs(:prepare).returns()
      end

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
      @provisioner.provision_and_watch_progress(@reporter, data['task_uuid'], data['nodes'], data['engine'])
    end

    it 'success report if all nodes were provisioned' do
      @provisioner.stubs(:report_about_progress).returns()
      @provisioner.stubs(:provision_piece).returns(nil)
      @provisioner.expects(:node_type).returns([{'uid' => '1', 'node_type' => 'target' }])
      @provisioner.stubs(:analize_node_types).returns([['1'], []])

      success_msg = {
        'status' => 'ready',
        'progress' => 100,
        'nodes' => [{
            'uid' => '1',
            'status' => 'provisioned',
            'progress' => 100}]}

      @reporter.expects(:report).with(success_msg).once
      @provisioner.provision_and_watch_progress(@reporter, data['task_uuid'], data['nodes'], data['engine'])
    end

    it 'success report if all nodes report about success at least once' do
      Astute.config.provisioning_timeout = 5
      nodes = [
        { 'uid' => '1'},
        { 'uid' => '2'}
      ]
      @provisioner.stubs(:report_about_progress).returns()
      @provisioner.stubs(:provision_piece).returns(nil)
      @provisioner.stubs(:node_type)
        .returns([{'uid' => '1', 'node_type' => 'target' }])
        .then.returns([{'uid' => '2', 'node_type' => 'target' }])

      success_msg = {
        'status' => 'ready',
        'progress' => 100,
        'nodes' => [{
            'uid' => '1',
            'status' => 'provisioned',
            'progress' => 100},
          {
            'uid' => '2',
            'status' => 'provisioned',
            'progress' => 100}
        ]}

      @reporter.expects(:report).with(success_msg).once
      @provisioner.provision_and_watch_progress(@reporter, data['task_uuid'], nodes, data['engine'])
    end

    it "unexpecting bootstrap nodes should be ereased and rebooted" do
      Astute.config.provisioning_timeout = 5
      nodes = [
        { 'uid' => '1'},
        { 'uid' => '2'}
      ]
      @provisioner.stubs(:report_about_progress).returns()
      @provisioner.stubs(:provision_piece).returns(nil)
      @provisioner.stubs(:node_type)
        .returns([{'uid' => '1', 'node_type' => 'target' }])
        .then.returns([{'uid' => '2', 'node_type' => 'bootstrap' }])
        .then.returns([{'uid' => '2', 'node_type' => 'bootstrap' }])
        .then.returns([{'uid' => '2', 'node_type' => 'target' }])

      Astute::NodesRemover.any_instance.expects(:remove)
                          .twice.returns({"nodes"=>[{"uid"=>"2", }]})

      success_msg = {
        'status' => 'ready',
        'progress' => 100,
        'nodes' => [{
            'uid' => '1',
            'status' => 'provisioned',
            'progress' => 100},
          {
            'uid' => '2',
            'status' => 'provisioned',
            'progress' => 100}
        ]}

      @reporter.expects(:report).with(success_msg).once
      @provisioner.provision_and_watch_progress(@reporter, data['task_uuid'], nodes, data['engine'])
    end

    it 'should provision nodes in chunks' do
      Astute.config.provisioning_timeout = 5
      Astute.config.max_nodes_to_provision = 2
      nodes = [
        { 'uid' => '1'},
        { 'uid' => '2'},
        { 'uid' => '3'}
      ]
      @provisioner.stubs(:report_about_progress).returns()
      @provisioner.stubs(:provision_piece).returns(nil)
      @provisioner.stubs(:node_type)
        .returns([{'uid' => '1', 'node_type' => 'target' }, {'uid' => '2', 'node_type' => 'target' }])
        .then.returns([{'uid' => '3', 'node_type' => 'target' }])

      success_msg = {
        'status' => 'ready',
        'progress' => 100,
        'nodes' => [{
            'uid' => '1',
            'status' => 'provisioned',
            'progress' => 100},
          {
            'uid' => '2',
            'status' => 'provisioned',
            'progress' => 100},
          {
            'uid' => '3',
            'status' => 'provisioned',
            'progress' => 100}
        ]}

      @provisioner.expects(:provision_piece).twice
      @reporter.expects(:report).with(success_msg).once
      @provisioner.provision_and_watch_progress(@reporter, data['task_uuid'], nodes, data['engine'])

    end

  end

  describe '#stop_provision' do
    around(:each) do |example|
      old_ssh_retries = Astute.config.ssh_retries
      old_mc_retries = Astute.config.mc_retries
      old_nodes_rm_interal = Astute.config.nodes_remove_interval
      example.run
      Astute.config.ssh_retries = old_ssh_retries
      Astute.config.mc_retries = old_mc_retries
      Astute.config.nodes_remove_interval = old_nodes_rm_interal
    end

    before(:each) do
      Astute.config.ssh_retries = 1
      Astute.config.mc_retries = 1
      Astute.config.nodes_remove_interval = 0
    end

    it 'erase nodes using ssh' do
      Astute::CobblerManager.any_instance.stubs(:remove_nodes).returns([])
      @provisioner.stubs(:stop_provision_via_mcollective).returns([[], {}])
      Astute::Ssh.stubs(:execute).returns({'inaccessible_nodes' => [{'uid' => 1}]}).once

      Astute::Ssh.expects(:execute).with(instance_of(Astute::Context),
                                        data['nodes'],
                                        Astute::SshEraseNodes.command)
                                   .returns({'nodes' => [{'uid' => 1}]})

      expect(@provisioner.stop_provision(@reporter,
                                   data['task_uuid'],
                                   data['engine'],
                                   data['nodes']))
            .to eql({
                     "error_nodes" => [],
                     "inaccessible_nodes" => [],
                     "nodes" => [{"uid"=>1}]
                    })
    end

    it 'always remove nodes from Cobbler' do
      Astute::Ssh.stubs(:execute).twice.returns({'inaccessible_nodes' => [{'uid' => 1}]})
      @provisioner.stubs(:stop_provision_via_mcollective).returns([[], {}])

      Astute::CobblerManager.any_instance.expects(:remove_nodes)
                                         .with(data['nodes'])
                                         .returns([])

      @provisioner.stop_provision(@reporter,
                                   data['task_uuid'],
                                   data['engine'],
                                   data['nodes'])
    end

    it 'reboot nodes using using ssh' do
      Astute::CobblerManager.any_instance.stubs(:remove_nodes).returns([])
      @provisioner.stubs(:stop_provision_via_mcollective).returns([[], {}])
      Astute::Ssh.stubs(:execute).returns({'nodes' => [{'uid' => 1}]}).once

      Astute::Ssh.expects(:execute).with(instance_of(Astute::Context),
                                       data['nodes'],
                                       Astute::SshHardReboot.command,
                                       timeout=5,
                                       retries=1)
                                 .returns({'inaccessible_nodes' => [{'uid' => 1}]})

      expect(@provisioner.stop_provision(@reporter,
                                   data['task_uuid'],
                                   data['engine'],
                                   data['nodes']))
            .to eql({
                     "error_nodes" => [],
                     "inaccessible_nodes" => [],
                     "nodes" => [{"uid"=>1}]
                    })
    end

    it 'stop provision if provision operation stop immediately' do
      @provisioner.stubs(:stop_provision_via_ssh)
                   .returns({'inaccessible_nodes' => [{'uid' => '1'}]})
      @provisioner.stubs(:node_type).returns([{'uid' => '1', 'node_type' => 'bootstrap'}])

      Astute::NodesRemover.any_instance.expects(:remove)
                          .once.returns({"nodes"=>[{"uid"=>"1", }]})

      expect(@provisioner.stop_provision(@reporter,
                                   data['task_uuid'],
                                   data['engine'],
                                   data['nodes']))
            .to eql({
                     "error_nodes" => [],
                     "inaccessible_nodes" => [],
                     "nodes" => [{"uid"=>"1"}]
                    })
    end

    it 'stop provision if provision operation stop in the end' do
      @provisioner.stubs(:stop_provision_via_ssh)
             .returns({'nodes' => [{'uid' => "1"}]})
      @provisioner.stubs(:node_type).returns([{'uid' => "1", 'node_type' => 'target'}])

      Astute::NodesRemover.any_instance.expects(:remove)
                          .once.returns({"nodes"=>[{"uid"=>"1", }]})

      expect(@provisioner.stop_provision(@reporter,
                                   data['task_uuid'],
                                   data['engine'],
                                   data['nodes']))
            .to eql({
                     "error_nodes" => [],
                     "inaccessible_nodes" => [],
                     "nodes" => [{"uid"=>"1"}]
                    })
    end

    it 'inform about inaccessible nodes' do
      Astute::Ssh.stubs(:execute).returns({'inaccessible_nodes' => [{'uid' => 1}]}).twice
      Astute::CobblerManager.any_instance.stubs(:remove_nodes).returns([])
      @provisioner.stubs(:node_type).returns([])

      Astute::NodesRemover.any_instance.expects(:remove).never

      expect(@provisioner.stop_provision(@reporter,
                             data['task_uuid'],
                             data['engine'],
                             data['nodes']))
            .to eql({
                     "error_nodes" => [],
                     "inaccessible_nodes" => [{"uid"=>1}],
                     "nodes" => []
                    })
    end

    it 'sleep between attempts to find and erase nodes using mcollective' do
      @provisioner.stubs(:stop_provision_via_ssh)
                   .returns({'inaccessible_nodes' => [{'uid' => '1'}]})
      @provisioner.stubs(:node_type).returns([{'uid' => '1', 'node_type' => 'bootstrap'}])
      Astute::NodesRemover.any_instance.stubs(:remove)
                          .once.returns({"nodes"=>[{"uid"=>"1", }]})

      @provisioner.expects(:sleep).with(Astute.config.nodes_remove_interval)

      @provisioner.stop_provision(@reporter,
                             data['task_uuid'],
                             data['engine'],
                             data['nodes'])
    end

    it 'perform several attempts to find and erase nodes using mcollective' do
      Astute.config.mc_retries = 2
      Astute.config.nodes_remove_interval = 0

      @provisioner.stubs(:stop_provision_via_ssh)
                   .returns({'nodes' => [{'uid' => "1"}],
                             'inaccessible_nodes' => [{'uid' => '2'}]})

      @provisioner.stubs(:node_type).twice
                   .returns([{'uid' => '1', 'node_type' => 'bootstrap'}])
                   .then.returns([{'uid' => '2', 'node_type' => 'target'}])

      Astute::NodesRemover.any_instance.stubs(:remove).twice
                          .returns({"nodes"=>[{"uid"=>"1"}]}).then
                          .returns({"error_nodes"=>[{"uid"=>"2"}]})

      data['nodes'] << {
        "uid" => '2',
        "slave_name"=>"controller-2",
        "admin_ip" =>'1.2.3.6'
      }

      expect(@provisioner.stop_provision(@reporter,
                             data['task_uuid'],
                             data['engine'],
                             data['nodes']))
            .to eql({
                     "error_nodes" => [{"uid"=>'2'}],
                     "inaccessible_nodes" => [],
                     "nodes" => [{"uid"=>"1"}],
                     "status" => "error"
                    })
    end

  end # stop_provision
end


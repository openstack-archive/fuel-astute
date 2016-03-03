#    Copyright 2016 Mirantis, Inc.
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
require 'json'

describe Astute::ImageProvision do
  include SpecHelpers

  let(:ctx) { mock_ctx }

  let(:provisioner) do
    provisioner = Astute::ImageProvision
    provisioner.stubs(:sleep)
    provisioner
  end

  let(:reporter) do
    reporter = mock('reporter')
    reporter.stub_everything
    reporter
  end

  let(:upload_task) { mock('upload_task') }

  let(:nodes) do
    [
      {
        'uid' => 5,
        "profile" => "ubuntu_1404_x86_64",
        "name_servers_search" => "test.domain.local"
      },
      {
        'uid' => 6,
        "profile" => "ubuntu_1404_x86_64",
        "name_servers_search" => "test.domain.local"
      }
    ]
  end

  describe ".provision" do
    it 'should upload provision info' do
      provisioner.stubs(:run_provision)
      provisioner.expects(:upload_provision).with(ctx, nodes)

      provisioner.provision(ctx, nodes)
    end

    it 'should run provision command' do
      provisioner.stubs(:upload_provision).returns([nodes.map {|n| n['uid']}, []])
      provisioner.expects(:run_provision).with(ctx, nodes.map {|n| n['uid']}, [])

      provisioner.provision(ctx, nodes)
    end

    it 'should exclude failed nodes from running provision command' do
      provisioner.stubs(:upload_provision).returns([[nodes.first['uid']], [nodes.last['uid']]])
      provisioner.expects(:run_provision).with(ctx, [nodes.first['uid']], [nodes.last['uid']])

      provisioner.provision(ctx, nodes)
    end

    it 'should return failed uids if catch exception' do
      provisioner.stubs(:upload_provision).returns([[nodes.first['uid']], [nodes.last['uid']]])
      provisioner.stubs(:run_provision).raises(Astute::AstuteError)

      expect(provisioner.provision(ctx, nodes)).to eql([6])
    end
  end

  describe ".reboot" do

    let(:reboot_hook) do
      {
        "priority" =>  100,
        "type" => "reboot",
        "fail_on_error" => false,
        "id" => 'reboot_provisioned_nodes',
        "uids" =>  node_ids,
        "parameters" => {
          "timeout" => Astute.config.reboot_timeout
        }
      }
    end

    let(:node_ids) { ['1', '2'] }

    it 'should reboot nodes using reboot nailgun hook' do
      nailgun_hook = mock('nailgun_hook')
      Astute::NailgunHooks.expects(:new)
                          .with([reboot_hook], ctx, 'provision')
                          .returns(nailgun_hook)
      nailgun_hook.expects(:process).once
      provisioner.reboot(ctx, node_ids, task_id="reboot_provisioned_nodes")
    end

    it 'should not run hook if no nodes present' do
      Astute::NailgunHooks.expects(:new).never
      provisioner.reboot(ctx, [], task_id="reboot_provisioned_nodes")
    end
  end

  describe ".upload_provision" do

    it 'should upload provision data on all nodes' do
      upload_task.stubs(:successful?).returns(true)

      provisioner.expects(:upload_provision_data)
                 .with(ctx, nodes[0])
                 .returns(true)
      provisioner.expects(:upload_provision_data)
                 .with(ctx, nodes[1])
                 .returns(false)

      provisioner.upload_provision(ctx, nodes)
    end

    it 'should return uids to provision and fail uids' do
      provisioner.stubs(:upload_provision_data)
                 .with(ctx, nodes[0])
                 .returns(false)
      provisioner.stubs(:upload_provision_data)
                 .with(ctx, nodes[1])
                 .returns(true)

      expect(provisioner.upload_provision(ctx, nodes)).to eql([[6],[5]])
    end
  end


  describe ".upload_provision_data" do
    let(:node) do
      {
        'uid' => 5,
        "profile" => "ubuntu_1404_x86_64",
        "name_servers_search" => "test.domain.local"
      }
    end

    let(:upload_file_task) do
      {
        "id" => 'upload_provision_data',
        "node_id" =>  node['uid'],
        "parameters" =>  {
          "path" => '/tmp/provision.json',
          "data" => node.to_json,
          "user_owner" => 'root',
          "group_owner" => 'root',
          "overwrite" => true
        }
      }
    end

    before(:each) do
      provisioner.stubs(:sleep)
    end

    it 'should upload provision using upload file task' do
      Astute::UploadFile.expects(:new)
                        .with(upload_file_task, ctx)
                        .returns(upload_task)
      upload_task.stubs(:sync_run).returns(true)

      provisioner.upload_provision_data(ctx, node)
    end

    it 'should return task status after finish' do
      Astute::UploadFile.stubs(:new).returns(upload_task)
      upload_task.expects(:sync_run).returns(false)

      expect(provisioner.upload_provision_data(ctx, node)).to eql(false)
    end
  end

  describe ".run_provision" do
    it 'should run provision on nodes using shell magent' do
      provisioner.expects(:run_shell_command).once.with(
        ctx,
        nodes.map { |n| n['uid'] },
        'flock -n /var/lock/provision.lock /usr/bin/provision',
        Astute.config.provisioning_timeout
      ).returns({5 => true, 6 => true})

      provisioner.run_provision(ctx, nodes.map { |n| n['uid'] }, [])
    end

    it 'should run return failed nodes' do
      provisioner.stubs(:run_shell_command).once.returns({5 => true, 6 => false})
      expect(provisioner.run_provision(ctx, nodes.map { |n| n['uid'] }, [])).to eql([6])
    end

    it 'should not erase info about alread failed nodes' do
      provisioner.stubs(:run_shell_command).once.returns({5 => true, 6 => false})
      failed_uids = [3]
      expect(provisioner.run_provision(
        ctx,
        nodes.map { |n| n['uid'] },
        failed_uids)
      ).to eql([3,6])
    end
  end

end


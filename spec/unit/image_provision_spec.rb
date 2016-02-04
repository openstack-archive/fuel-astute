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

  let(:node_ids) { ['1', '2'] }

  let(:reboot_hook) do
    {
      "priority" =>  100,
      "type" => "reboot",
      "fail_on_error" => false,
      "id" => 'reboot_provisioned_nodes',
      "uids" =>  node_ids,
      "parameters" =>  {
        "timeout" =>  Astute.config.reboot_timeout
      }
    }
  end

  describe ".reboot" do
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

end


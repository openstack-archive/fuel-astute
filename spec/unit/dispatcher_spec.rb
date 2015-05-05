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

describe Astute::Server::Dispatcher do
  include SpecHelpers

  context "remove_nodes" do
    let(:dispatcher) do
      dispatcher = Astute::Server::Dispatcher.new(mock)
      dispatcher.stubs(:report_result)
      dispatcher.stubs(:check_for_offline_nodes).returns(true)

      dispatcher
    end

    let (:orchestrator) do
      orchestrator = Astute::Orchestrator.any_instance
      orchestrator.stubs(:remove_nodes)

      orchestrator
    end

    let (:data) {
      {'args' => {
        'task_uuid' => '0000-0000',
        'respond_to' => 'remove_nodes_resp',
        'engine' => 'engine',
        'check_ceph' => true,
        'nodes' => [{}]
        }
      }
    }

    it 'should not call remove_nodes_ceph_check' do
      data['args']['check_ceph'] = false
      orchestrator.expects(:remove_nodes).once
      dispatcher.expects(:remove_nodes_ceph_check).never
      dispatcher.remove_nodes(data)
    end

    it 'should not remove nodes when check fails' do
      dispatcher.stubs(:remove_nodes_ceph_check).returns(false)
      orchestrator.expects(:remove_nodes).never
      dispatcher.remove_nodes(data)
    end

    it 'should remove nodes when check passes' do
      dispatcher.stubs(:remove_nodes_ceph_check).returns(true)
      orchestrator.expects(:remove_nodes).once
      dispatcher.remove_nodes(data)
    end
  end

end

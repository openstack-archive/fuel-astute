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

  describe "#remove_nodes" do
    let(:dispatcher) do
      dispatcher = Astute::Server::Dispatcher.new(mock)
      dispatcher.stubs(:report_result)

      dispatcher
    end

    let (:orchestrator) do
      orchestrator = Astute::Orchestrator.any_instance
      orchestrator.stubs(:check_for_offline_nodes).returns({"status"=>"ready"})

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

    it 'should not call check_ceph_osds' do
      data['args']['check_ceph'] = false
      Astute::Provisioner.any_instance.expects(:remove_nodes).once
      orchestrator.expects(:check_ceph_osds).never
      dispatcher.remove_nodes(data)
    end

    it 'should not remove nodes when check fails' do
      Astute::Provisioner.any_instance.expects(:remove_nodes).never
      orchestrator.stubs(:check_ceph_osds).returns({"status" => "error"})
      dispatcher.remove_nodes(data)
    end

    it 'should remove nodes when check passes' do
      orchestrator.stubs(:check_ceph_osds).returns({"status" => "ready"}).once
      orchestrator.stubs(:remove_ceph_mons).returns({"status" => "ready"}).once
      Astute::Provisioner.any_instance.expects(:remove_nodes).once
      dispatcher.remove_nodes(data)
    end
  end

  describe "#stop_deploy_task" do
    let (:dispatcher) do
      dispatcher = Astute::Server::Dispatcher.new(mock)

      dispatcher
    end

    let (:orchestrator) do
      orchestrator = Astute::Orchestrator.any_instance

      orchestrator
    end

    let (:data) {
      {'args' => {
        'task_uuid' => '0000-0000',
        'stop_task_uuid' => '0000-0000',
        'engine' => 'engine',
        'nodes' => [{'uid' => 1}]
        }
      }
    }

    let (:service_data) do
      task_queue = mock()
      task_queue.stubs(:task_in_queue?).returns(true)
      task_queue.stubs(:current_task_id).returns('0000-0000')

      {:tasks_queue => task_queue}
    end

    it 'should stop deployment' do
      service_data[:tasks_queue].stubs(:current_task_method).returns('deploy')
      dispatcher.expects(:kill_main_process).with('0000-0000', service_data)
      orchestrator.expects(:stop_puppet_deploy).with(anything, '0000-0000', [{'uid' => 1}])
      orchestrator.expects(:remove_nodes).with(anything, '0000-0000', 'engine', [{'uid' => 1}])
        .returns({'nodes' => [{'uid' => 1}]})
      dispatcher.expects(:report_result).with({'nodes' => [{'uid' => 1}]}, anything)
      dispatcher.stop_deploy_task(data, service_data)
    end

    it 'should stop task deployment' do
      service_data[:tasks_queue].stubs(:current_task_method).returns('task_deploy')
      dispatcher.expects(:gracefully_stop_main_process).with('0000-0000', service_data)
      dispatcher.expects(:wait_while_process_run).with(anything, anything, '0000-0000', service_data)
        .returns({})
      dispatcher.expects(:report_result).with({'nodes' => [{'uid' => 1}]}, anything)
      dispatcher.stop_deploy_task(data, service_data)
    end

    it 'should stop provisioning' do
      service_data[:tasks_queue].stubs(:current_task_method).returns('provision')
      dispatcher.expects(:kill_main_process).with('0000-0000', service_data)
      orchestrator.expects(:stop_provision).with(anything, '0000-0000', 'engine', [{'uid' => 1}])
        .returns({'nodes' => [{'uid' => 1}]})
      dispatcher.expects(:report_result).with({'nodes' => [{'uid' => 1}]}, anything)
      dispatcher.stop_deploy_task(data, service_data)
    end

  end

end

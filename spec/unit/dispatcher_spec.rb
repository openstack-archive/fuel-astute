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

    let (:reset_data) {
      {"pre_reset_tasks"=>[
        {
          "parameters"=>{
            "cmd"=>"rm -rf /var/lib/fuel/keys/1",
            "cwd"=>"/",
            "interval"=>1,
            "retries"=>3,
            "timeout"=>30
          },
        "type"=>"shell",
        "uids"=>["master"]
        }
      ]}
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

    it 'should call pre_reset_tasks before restarting nodes' do
      dispatcher.expects(:pre_reset_tasks).once
      dispatcher.reset_environment(reset_data)
    end
  end

end

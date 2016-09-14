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

require 'spec_helper'
require 'set'

describe Deployment::Cluster do

  let(:cluster) do
    cluster = Deployment::Cluster.new
    cluster.uid = 'test'
    node1 = cluster.create_node 'node1'
    node2 = cluster.create_node 'node2'
    node1.create_task 'task1'
    node1.create_task 'task2'
    node1.create_task 'task3'
    node1.create_task 'task4'
    node2.create_task 'task1'
    node2.create_task 'task2'
    cluster
  end

  let(:node1) do
    cluster['node1']
  end

  let(:node2) do
    cluster['node2']
  end

  let(:task1_1) do
    cluster['node1']['task1']
  end

  let(:task1_2) do
    cluster['node1']['task2']
  end

  let(:task1_3) do
    cluster['node1']['task3']
  end

  let(:task1_4) do
    cluster['node1']['task4']
  end

  let(:task2_1) do
    cluster['node2']['task1']
  end

  let(:task2_2) do
    cluster['node2']['task2']
  end

  subject { cluster }

  context '#attributes' do
    it 'has an id' do
      expect(subject.uid).to eq 'test'
    end

    it 'can set an id' do
      subject.uid = 1
      expect(subject.uid).to eq 1
    end

    it 'has nodes' do
      expect(subject.nodes).to eq({:node1 => node1, :node2 => node2})
    end

    it 'has node_concurrency' do
      expect(subject.node_concurrency).to be_a Deployment::Concurrency::Counter
    end

    it 'has task_concurrency' do
      expect(subject.task_concurrency).to be_a Deployment::Concurrency::Group
    end

  end

  context '#nodes processing' do
    it 'can check that the node is in the cluster' do
      expect(cluster.node_present? 'node1').to eq true
      expect(cluster.node_present? node1).to eq true
      expect(cluster.node_present? 'node3').to eq false
    end

    it 'can add an existing node' do
      node3 = Deployment::Node.new 'node3', cluster
      cluster.node_remove node3
      expect(cluster.node_present? node3).to eq false
      return_node = cluster.node_add node3
      expect(cluster.node_present? node3).to eq true
      expect(return_node).to eq node3
    end

    it 'will add only the valid node objects' do
      expect do
        subject.node_add 'node1'
      end.to raise_exception Deployment::InvalidArgument, /can add only nodes/
      expect do
        subject.node_add ['node1']
      end.to raise_exception Deployment::InvalidArgument, /can add only nodes/
    end

    it 'can move a node from the other cluster by adding it' do
      another_cluster = Deployment::Cluster.new
      node3 = another_cluster.node_create 'node3'
      expect(node3.name).to eq 'node3'
      expect(node3.cluster).to eq another_cluster
      expect(another_cluster.node_present? 'node3').to eq true
      expect(cluster.node_present? 'node3').to eq false
      cluster.node_add node3
      expect(node3.cluster).to eq cluster
      expect(cluster.node_present? 'node3').to eq true
      expect(another_cluster.node_present? 'node3').to eq false
    end

    it 'can get an existing node by its name' do
      expect(cluster.node_get 'node1').to eq node1
      expect(cluster.node_get node1).to eq node1
      expect(cluster['node1']).to eq node1
    end

    it 'can create a new node' do
      return_node = cluster.node_create 'node3'
      expect(return_node.name).to eq 'node3'
      expect(cluster.node_get 'node3').to eq return_node
    end

    it 'can remove an existing node' do
      expect(cluster.node_present? 'node1').to eq true
      expect(cluster.node_present? 'node2').to eq true
      cluster.node_remove 'node1'
      cluster.node_remove node2
      expect(cluster.node_present? 'node1').to eq false
      expect(cluster.node_remove 'node3').to be_nil
    end

    it 'can iterate through all nodes' do
      expect(subject.each_node.to_set).to eq Set.new([node1, node2])
    end

    it 'can iterate through all tasks' do
      expect(subject.each_task.to_set).to eq Set.new([task1_1, task1_2, task1_3, task1_4, task2_1, task2_2])
    end

    it 'can iterate through all ready tasks' do
      task1_2.after task1_1
      task1_3.after task1_2
      task1_4.after task1_3
      task2_2.after task2_1
      expect(subject.each_ready_task.to_set).to eq Set.new([task1_1, task2_1])
    end

    it 'can check if all nodes are finished' do
      task1_1.status = :successful
      task1_2.status = :successful
      task1_3.status = :skipped
      task1_4.status = :failed
      task2_1.status = :successful
      task2_2.status = :pending
      expect(subject.all_nodes_are_finished?).to eq false
      task2_2.status = :successful
      expect(subject.all_nodes_are_finished?).to eq true
    end

    it 'can check if all nodes are successful' do
      task1_1.status = :successful
      task1_2.status = :successful
      task1_3.status = :successful
      task1_4.status = :failed
      task2_1.status = :successful
      task2_2.status = :successful
      expect(subject.all_nodes_are_successful?).to eq false
      task1_4.status = :successful
      expect(subject.all_nodes_are_successful?).to eq true
    end

    it 'can find failed nodes' do
      task1_1.status = :successful
      task1_2.status = :successful
      task2_1.status = :successful
      task2_2.status = :pending
      expect(subject.failed_nodes).to eq([])
      expect(subject.has_failed_nodes?).to eq false
      task2_2.status = :failed
      expect(subject.failed_nodes).to eq([node2])
      expect(subject.has_failed_nodes?).to eq true
    end

    context 'fault_tolerance_groups' do

      let(:fault_tolerance_groups) do
        [{
           "fault_tolerance"=>1,
           "name"=>"test_group",
           "node_ids"=>['node2']
         },
         {
           "fault_tolerance"=> 0,
           "name"=>"test_group2",
           "node_ids"=>[]
          }]
      end

      it 'can find tolerance group' do
        cluster.fault_tolerance_groups = fault_tolerance_groups
        task1_1.status = :successful
        task1_2.status = :successful
        task2_1.status = :successful
        task2_2.status = :failed
        expect(cluster.fault_tolerance_groups).to eq [fault_tolerance_groups.first]
      end

      it 'can validate tolerance group' do
        cluster.fault_tolerance_groups = fault_tolerance_groups
        task1_1.status = :successful
        task1_2.status = :successful
        task2_1.status = :failed
        cluster.validate_fault_tolerance(node1)
        cluster.validate_fault_tolerance(node2)
        expect(cluster.fault_tolerance_excess?).to eq false
        expect(cluster.gracefully_stop?).to eq false
      end

      it 'can control deploy using tolerance group' do
        fault_tolerance_groups.first['fault_tolerance'] = 0
        cluster.fault_tolerance_groups = fault_tolerance_groups
        task1_1.status = :successful
        task1_2.status = :successful
        task2_1.status = :failed
        cluster.validate_fault_tolerance(node1)
        cluster.validate_fault_tolerance(node2)
        expect(cluster.fault_tolerance_excess?).to eq true
        expect(cluster.gracefully_stop?).to eq true
      end
    end

    it 'can find critical nodes' do
      expect(subject.critical_nodes).to eq([])
      node1.critical = true
      expect(subject.critical_nodes).to eq([node1])
    end

    it 'can find failed critical nodes' do
      expect(subject.failed_critical_nodes).to eq([])
      expect(subject.has_failed_critical_nodes?).to eq false
      node1.critical = true
      expect(subject.failed_critical_nodes).to eq([])
      expect(subject.has_failed_critical_nodes?).to eq false
      task1_1.status = :failed
      expect(subject.failed_critical_nodes).to eq([node1])
      expect(subject.has_failed_critical_nodes?).to eq true
      task1_1.status = :pending
      node1.status = :failed
      expect(subject.failed_critical_nodes).to eq([node1])
      expect(subject.has_failed_critical_nodes?).to eq true
      node2.status = :failed
      expect(subject.failed_critical_nodes).to eq([node1])
      expect(subject.has_failed_critical_nodes?).to eq true
    end

    it 'can count the total tasks number' do
      expect(subject.tasks_total_count).to eq 6
    end

    it 'can count the failed tasks number' do
      task1_1.status = :successful
      task1_2.status = :failed
      task2_1.status = :successful
      task2_2.status = :failed
      expect(subject.tasks_failed_count).to eq 2
    end

    it 'can count the successful tasks number' do
      task1_1.status = :successful
      task1_2.status = :successful
      task2_1.status = :successful
      task2_2.status = :pending
      expect(subject.tasks_successful_count).to eq 3
    end

    it 'can count the finished tasks number' do
      task1_1.status = :successful
      task1_2.status = :failed
      task2_1.status = :successful
      task2_2.status = :pending
      expect(subject.tasks_finished_count).to eq 3
    end

    it 'can count the pending tasks number' do
      task1_1.status = :successful
      task1_2.status = :failed
      expect(subject.tasks_pending_count).to eq 4
    end

    it 'can count the ending tasks' do

    end
  end

  context '#dfs' do
    context '#no loop' do
      let(:link_without_loop) do
        cluster
        task1_2.after task1_1
        task1_3.after task1_1
        task1_4.after task1_2
        task1_4.after task1_3
        task2_1.after task1_4
        task2_2.after task2_1
      end

      before(:each) do
        link_without_loop
      end

      it 'can walk forward' do
        visited = Set.new
        cluster.visit(task1_1).each do |t|
          visited.add t
        end
        expect(visited).to eq [task1_1, task1_2, task1_4, task2_1, task2_2, task1_3].to_set
      end

      it 'can walk backward' do
        visited = Set.new
        cluster.visit(task2_2, direction: :backward).each do |t|
          visited.add t
        end
        expect(visited).to eq [task2_2, task2_1, task1_4, task1_2, task1_1, task1_3].to_set
      end

      it 'can topology sort' do
        expect(cluster.topology_sort).to eq [task1_1, task1_3, task1_2, task1_4, task2_1, task2_2]
      end

      it 'can check if there is no loop' do
        expect(cluster.has_loop?).to eq false
      end
    end

    context '#has loop' do
      let(:link_with_loop) do
        task1_2.after task1_1
        task1_3.after task1_2
        task1_4.after task1_3
        task1_1.after task1_4
        task2_1.after task1_4
        task2_2.after task2_1
      end

      before(:each) do
        link_with_loop
      end

      it 'can walk forward' do
        message = 'Cluster[test]: Loop detected! Path: Task[task1/node1], Task[task2/node1], Task[task3/node1], Task[task4/node1], Task[task1/node1]'
        expect do
          cluster.visit(task1_1).to_a
        end.to raise_error Deployment::LoopDetected, message
      end

      it 'can walk backward' do
        message = 'Cluster[test]: Loop detected! Path: Task[task1/node1], Task[task4/node1], Task[task3/node1], Task[task2/node1], Task[task1/node1]'
        expect do
          cluster.visit(task1_1, direction: :backward).to_a
        end.to raise_error Deployment::LoopDetected, message
      end

      it 'can topology sort' do
        message = 'Cluster[test]: Loop detected! Path: Task[task1/node1], Task[task2/node1], Task[task3/node1], Task[task4/node1], Task[task1/node1]'
        expect do
          cluster.topology_sort
        end.to raise_error Deployment::LoopDetected, message
      end

      it 'can check if there is no loop' do
        expect(cluster.has_loop?).to eq true
      end

    end
  end

  context '#inspection' do
    it 'can to_s' do
      expect(subject.to_s).to eq 'Cluster[test]'
    end

    it 'can inspect' do
      expect(subject.inspect).to eq 'Cluster[test]{Tasks: 0/6 Nodes: node1, node2}'
    end

    it 'can generate dot graph' do
      graph = <<-eof
digraph "test" {
  node[ style = "filled, solid"];
  "Task[task1/node1]" [label = "Task[task1/node1]", fillcolor = "yellow"];
  "Task[task2/node1]" [label = "Task[task2/node1]", fillcolor = "white"];
  "Task[task3/node1]" [label = "Task[task3/node1]", fillcolor = "white"];
  "Task[task4/node1]" [label = "Task[task4/node1]", fillcolor = "white"];
  "Task[task1/node2]" [label = "Task[task1/node2]", fillcolor = "yellow"];
  "Task[task2/node2]" [label = "Task[task2/node2]", fillcolor = "yellow"];

  "Task[task1/node1]" -> "Task[task2/node1]";
  "Task[task1/node1]" -> "Task[task3/node1]";
  "Task[task2/node1]" -> "Task[task4/node1]";
  "Task[task3/node1]" -> "Task[task4/node1]";
}
      eof

      task1_2.after task1_1
      task1_3.after task1_1
      task1_4.after task1_2
      task1_4.after task1_3
      expect(cluster.to_dot).to eq graph
    end
  end
end

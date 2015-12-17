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

describe Deployment::Graph do

  let(:cluster) do
    cluster = Deployment::Cluster.new
    cluster.id = 'test'
    node1 = cluster.create_node 'node1'
    node2 = cluster.create_node 'node2'
    node1.create_task 'task1'
    node1.create_task 'task2'
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

  let(:graph1) do
    node1.graph
  end

  let(:graph2) do
    node2.graph
  end

  let(:task1_1) do
    cluster['node1']['task1']
  end

  let(:task1_2) do
    cluster['node1']['task2']
  end

  let(:task2_1) do
    cluster['node2']['task1']
  end

  let(:task2_2) do
    cluster['node2']['task2']
  end

  subject { graph1 }

  context '#attributes' do
    it 'should have a node' do
      expect(subject.node).to eq node1
      expect(subject.name).to eq node1.name
    end

    it 'should have a tasks' do
      expect(subject.tasks).to be_a Hash
    end

    it 'can set node only to a node object' do
      subject.node = node2
      expect(subject.node).to eq node2
      expect do
        subject.node = 'node3'
      end.to raise_error Deployment::InvalidArgument, /Not a node/
    end
  end

  context '#tasks' do
    it 'can create a new task' do
      task = subject.task_create 'new_task'
      expect(task.name).to eq 'new_task'
      expect(task.node.name).to eq 'node1'
    end

    it 'can create a new task with data payload value' do
      task = subject.task_create 'new_task', 'my_data'
      expect(task.name).to eq 'new_task'
      expect(task.node.name).to eq 'node1'
      expect(task.data).to eq 'my_data'
    end

    it 'creating an existing task will return it and update the data payload' do
      task1 = subject.task_create 'new_task'
      expect(task1.data).to be_nil
      task2 = subject.task_create 'new_task', 'my_data'
      expect(task2.data).to eq 'my_data'
      expect(task1).to eq task2
    end

    it 'can add an existing task' do
      task = task1_1
      subject.task_remove task
      subject.task_add task
      expect(task.name).to eq 'task1'
      expect(task.node.name).to eq 'node1'
    end

    it 'will move a task from another graph by adding it' do
      another_node = cluster.node_create 'node3'
      another_task = another_node.graph.task_create 'another_task'
      expect(another_task.name).to eq 'another_task'
      expect(another_task.node).to eq another_node
      expect(another_node.graph.task_present? 'another_task').to eq true
      expect(node1.graph.task_present? 'another_task').to eq false
      node1.graph.task_add another_task
      expect(another_task.node).to eq node1
      expect(node1.graph.task_present? 'another_task').to eq true
      expect(another_node.graph.task_present? 'another_task').to eq false
    end

    it 'can check if a task is present' do
      task = task1_1
      subject.task_remove task
      expect(subject.task_present? 'task1').to eq false
      subject.task_add task
      expect(subject.task_present? 'task1').to eq true
      expect(subject.task_present? task1_1).to eq true
    end

    it 'can get an existing task' do
      expect(subject.task_get 'task1').to eq task1_1
      expect(subject['task1']).to eq task1_1
      expect(subject.task_get task1_1).to eq task1_1
      expect(subject.task_get 'missing_task').to eq nil
    end

    it 'can remove a task' do
      expect(subject.task_present? 'task1').to eq true
      subject.task_remove task1_1
      expect(subject.task_present? 'task1').to eq false
    end

    it 'can add dependencies between tasks of the same graph by name' do
      subject.add_dependency 'task1', 'task2'
      expect(subject['task2'].dependency_present? task1_1).to eq true
    end

    it 'will not add dependencies if there is no such task' do
      expect do
        subject.add_dependency 'task1', 'task3'
      end.to raise_exception Deployment::NoSuchTask, /no such task in the graph/
    end

    it 'can add dependencies between task objects of the same graph' do
      subject.add_dependency task1_1, task1_2
      expect(subject[task1_2].dependency_present? task1_1).to eq true
    end

    it 'can add dependencies between task objects in the different graphs' do
      subject.add_dependency task1_2, task2_2
      expect(graph2[task2_2].dependency_present? task1_2).to eq true
    end

    it 'can iterate through tasks' do
      expect(subject.each.to_a).to eq [task1_1, task1_2]
    end

    it 'can add a new task together with the list of its dependencies' do
      subject.task_add_new_with_dependencies 'new_task', 'new_data', %w(bd1 bd2), %w(fd1 fd2)
      expect(subject['new_task'].data).to eq 'new_data'
      expect(subject['new_task'].dependency_backward_present? subject['bd1']).to eq true
      expect(subject['new_task'].dependency_backward_present? subject['bd2']).to eq true
      expect(subject['new_task'].dependency_forward_present? subject['fd1']).to eq true
      expect(subject['new_task'].dependency_forward_present? subject['fd2']).to eq true
    end

    it 'can add a task together with the list of task object dependencies' do
      subject.task_add_new_with_dependencies task1_2, 'data', [task1_1]
      expect(subject.tasks.length).to eq 2
      expect(task1_1.dependency_forward_present? task1_2).to eq true
    end
  end

  context '#tasks advanced' do
    it 'can determine that all tasks are finished' do
      expect(subject.tasks_are_finished?).to eq false
      task1_1.status = :successful
      task1_2.status = :failed
      subject.reset
      expect(subject.tasks_are_finished?).to eq true
    end

    it 'can determine that all tasks are successful' do
      expect(subject.tasks_are_successful?).to eq false
      task1_1.status = :successful
      task1_2.status = :successful
      subject.reset
      expect(subject.tasks_are_successful?).to eq true
    end

    it 'can determine that some tasks are failed' do
      expect(subject.tasks_have_failed?).to eq false
      task1_1.status = :successful
      task1_2.status = :failed
      subject.reset
      expect(subject.tasks_have_failed?).to eq true
    end

    it 'can get a runnable task' do
      task1_2.after task1_1
      expect(subject.ready_task).to eq task1_1
      task1_1.status = :failed
      expect(subject.ready_task).to be_nil
    end

    it 'uses task dependencies to determine a runnable task' do
      subject.add_dependency task1_1, task1_2
      expect(subject.ready_task).to eq task1_1
      task1_1.status = :successful
      expect(subject.ready_task).to eq task1_2
      task1_1.status = :failed
      task1_2.poll_dependencies
      expect(subject.ready_task).to be_nil
    end

    it 'can count the total tasks number' do
      expect(subject.tasks_total_count).to eq 2
    end

    it 'can count the failed tasks number' do
      task1_2.status = :failed
      expect(subject.tasks_failed_count).to eq 1
    end

    it 'can count the successful tasks number' do
      task1_2.status = :successful
      expect(subject.tasks_successful_count).to eq 1
    end

    it 'can count the finished tasks number' do
      task1_2.status = :successful
      expect(subject.tasks_finished_count).to eq 1
      task1_2.status = :skipped
      expect(subject.tasks_finished_count).to eq 1
    end

    it 'can count the pending tasks number' do
      expect(subject.tasks_pending_count).to eq 2
    end
  end

  context '#inspections' do

    it 'can to_s' do
      expect(subject.to_s).to eq 'Graph[node1]'
    end

    it 'can inspect' do
      expect(subject.inspect).to eq 'Graph[node1]{Tasks: 0/2 Finished: false Failed: false Successful: false}'
      subject.task_add task1_1
      expect(subject.inspect).to eq 'Graph[node1]{Tasks: 0/2 Finished: false Failed: false Successful: false}'
      task1_1.status = :successful
      subject.reset
      expect(subject.inspect).to eq 'Graph[node1]{Tasks: 1/2 Finished: false Failed: false Successful: false}'
      task1_1.status = :failed
      subject.reset
      expect(subject.inspect).to eq 'Graph[node1]{Tasks: 1/2 Finished: false Failed: true Successful: false}'
    end

  end
end

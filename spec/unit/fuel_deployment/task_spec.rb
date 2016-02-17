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

describe Deployment::Task do

  let(:cluster) do
    cluster = Deployment::Cluster.new
    cluster.id = 'test'
    node1 = cluster.create_node 'node1'
    node2 = cluster.create_node 'node2'
    node1.create_task 'task1'
    node1.create_task 'task2'
    node1.create_task 'task3'
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

  let(:task1) do
    cluster['node1']['task1']
  end

  let(:task2) do
    cluster['node1']['task2']
  end

  let(:task3) do
    cluster['node1']['task3']
  end

  let(:task2_1) do
    cluster['node2']['task1']
  end

  let(:task2_2) do
    cluster['node2']['task2']
  end

  subject { task1 }

  context '#attributes' do
    it 'should have a name' do
      expect(subject.name).to eq 'task1'
    end

    it 'should have a node' do
      expect(subject.node).to eq node1
    end

    it 'should have a status' do
      expect(subject.status).to eq :pending
    end

    it 'should have a required' do
      expect(subject.backward_dependencies).to eq Set.new
    end

    it 'should have a data' do
      expect(subject.data).to eq nil
    end

    it 'should set name as a string' do
      subject.name = 'task3'
      expect(subject.name).to eq 'task3'
      subject.name = 1
      expect(subject.name).to eq '1'
    end

    it 'should set node only to a node object' do
      subject.node = node2
      expect(subject.node).to eq node2
      expect do
        subject.node = 'node3'
      end.to raise_error Deployment::InvalidArgument, /Not a node/
    end

    it 'should set only a correct status' do
      subject.status = :successful
      expect(subject.status).to eq :successful
      subject.status = 'failed'
      expect(subject.status).to eq :failed
      expect do
        subject.status = 'on'
      end.to raise_error Deployment::InvalidArgument, /Invalid task status/
    end

    it 'can set data' do
      subject.data = 'my data'
      expect(subject.data).to eq 'my data'
    end

    it 'can use dynamic status setters' do
      subject.set_status_failed
      expect(subject.status).to eq :failed
    end

    it 'can determine its color' do
      task2_2.after task2_1
      expect(task2_1.color).to eq :yellow
      expect(task2_2.color).to eq :white
      task2_1.status = :failed
      expect(task2_1.color).to eq :red
      expect(task2_2.color).to eq :magenta
      task2_1.status = :running
      task2_2.status = :pending
      expect(task2_1.color).to eq :blue
      expect(task2_2.color).to eq :white
      task2_1.status = :successful
      task2_2.status = :pending
      expect(task2_1.color).to eq :green
      expect(task2_2.color).to eq :yellow
      task2_1.status = :skipped
      task2_2.status = :pending
      expect(task2_1.color).to eq :purple
      expect(task2_2.color).to eq :yellow
    end

    it 'can determine the task weight for a single node' do
      task2.after task1
      task3.after task2
      expect(task3.weight).to eq 0
      expect(task2.weight).to eq 1
      expect(task1.weight).to eq 2
    end

    it 'can determine the task weight between nodes' do
      task2.after task1
      task2_1.after task2
      expect(task2.weight).to eq 10
      expect(task1.weight).to eq 11
      expect(task2_1.weight).to eq 0
    end

    it 'should add itself to the node when the task is created' do
      expect(node1.task_present? 'task5').to eq false
      Deployment::Task.new 'task5', node1
      expect(node1.task_present? 'task5').to eq true
    end
  end

  context '#dependencies basic' do
    it 'can add a backward dependency task' do
      subject.dependency_backward_add task2
      expect(subject.backward_dependencies).to eq Set[task2]
    end

    it 'can add a forward dependency task' do
      subject.dependency_forward_add task2
      expect(subject.forward_dependencies).to eq Set[task2]
    end

    it 'can only add tasks as backward dependencies' do
      expect do
        subject.dependency_backward_add 'dep1'
      end.to raise_error Deployment::InvalidArgument, /should be a task/
    end

    it 'can only add tasks as forward dependencies' do
      expect do
        subject.dependency_forward_add 'dep1'
      end.to raise_error Deployment::InvalidArgument, /should be a task/
    end

    it 'will not try to add dependency to self' do
      task1.dependency_backward_add task1
      expect(task1.dependency_backward_present? task1).to eq false
      task1.dependency_forward_add task1
      expect(task1.dependency_forward_present? task1).to eq false
    end

    it 'can determine if there are backward dependencies' do
      expect(subject.dependency_backward_any?).to eq false
      subject.dependency_backward_add task2
      expect(subject.dependency_backward_any?).to eq true
    end

    it 'can determine if there are forward dependencies' do
      expect(subject.dependency_forward_any?).to eq false
      subject.dependency_forward_add task2
      expect(subject.dependency_forward_any?).to eq true
    end

    it 'can remove a forward dependency' do
      subject.dependency_backward_add task2
      expect(subject.backward_dependencies).to eq Set[task2]
      subject.dependency_backward_remove task2
      expect(subject.backward_dependencies).to eq Set.new
    end

    it 'can remove a backward dependency' do
      subject.dependency_forward_add task2
      expect(subject.forward_dependencies).to eq Set[task2]
      subject.dependency_forward_remove task2
      expect(subject.forward_dependencies).to eq Set.new
    end

    it 'can check if a task has the specific backward dependency' do
      expect(subject.dependency_backward_present? task2).to eq false
      subject.dependency_backward_add task2
      expect(subject.dependency_backward_present? task2).to eq true
      expect(subject.dependency_backward_present? task3).to eq false
    end

    it 'can check if a task has the specific forward dependency' do
      expect(subject.dependency_forward_present? task2).to eq false
      subject.dependency_forward_add task2
      expect(subject.dependency_forward_present? task2).to eq true
      expect(subject.dependency_forward_present? task3).to eq false
    end

    it 'can iterate through backward dependencies' do
      subject.dependency_backward_add task2
      dependencies = subject.each_backward_dependency.to_a
      expect(dependencies).to eq [task2]
    end

    it 'can iterate through forward dependencies' do
      subject.dependency_forward_add task2
      dependencies = subject.each_forward_dependency.to_a
      expect(dependencies).to eq [task2]
    end

    it 'defaults all actions to the backward dependencies' do
      actions = {
          :dependency_add => :dependency_backward_add,
          :dependency_remove => :dependency_backward_remove,
          :dependency_present? => :dependency_backward_present?,
          :dependency_any? => :dependency_backward_any?,
          :each => :each_backward_dependency,
      }
      actions.each do |method_alias, method_name|
        expect(subject.method method_alias).to eq subject.method method_name
      end
    end
  end

  context '#dependencies advanced' do
    it 'dependencies are met if there are no dependencies' do
      expect(task1.dependency_backward_any?).to eq false
      expect(task1.ready?).to eq true
    end

    it 'there are no dependency errors if there are no dependencies' do
      expect(task1.dependency_backward_any?).to eq false
      expect(task1.failed?).to eq false
    end

    it 'can detect that task is ready to run by its status' do
      expect(task1.ready?).to eq true
      task1.status = :successful
      expect(task1.ready?).to eq false
      task1.status = :skipped
      expect(task1.ready?).to eq false
      task1.status = :failed
      expect(task1.ready?).to eq false
    end

    it 'can detect different task statuses' do
      task1.status = :pending
      expect(task1.pending?).to eq true
      task1.status = :successful
      expect(task1.successful?).to eq true
      task1.status = :skipped
      expect(task1.skipped?).to eq true
      task1.status = :running
      expect(task1.running?).to eq true
      task1.status = :failed
      expect(task1.failed?).to eq true
    end

    it 'can detect that task is ready by dependencies' do
      task1.dependency_backward_add task2
      expect(task1.ready?).to eq false
      task2.status = :successful
      expect(task1.ready?).to eq true
    end

    it 'can detect that direct dependencies are failed' do
      task1.dependency_backward_add task2
      expect(task1.failed?).to eq false
      expect(task2.failed?).to eq false
      task2.status = :failed
      expect(task1.failed?).to eq true
      expect(task2.failed?).to eq true
    end

    it 'can detect that far dependencies are failed' do
      task1.dependency_backward_add task2
      task2.dependency_backward_add task3
      expect(task1.failed?).to eq false
      expect(task2.failed?).to eq false
      expect(task3.failed?).to eq false
      task3.status = :failed
      task2.poll_dependencies
      task3.poll_dependencies
      expect(task1.failed?).to eq true
      expect(task2.failed?).to eq true
      expect(task3.failed?).to eq true
    end

  end

  context '#inspection' do

    it 'can to_s' do
      expect(subject.to_s).to eq 'Task[task1/node1]'
    end

    it 'can inspect' do
      expect(subject.inspect).to eq 'Task[task1/node1]{Status: pending}'
      subject.status = :failed
      expect(subject.inspect).to eq 'Task[task1/node1]{Status: failed}'
      subject.dependency_backward_add task2
      expect(subject.inspect).to eq 'Task[task1/node1]{Status: failed After: Task[task2/node1]}'
      subject.dependency_backward_add task2_1
      expect(subject.inspect).to eq 'Task[task1/node1]{Status: failed After: Task[task1/node2], Task[task2/node1]}'
      subject.dependency_forward_add task2_2
      expect(subject.inspect).to eq 'Task[task1/node1]{Status: failed After: Task[task1/node2], Task[task2/node1] Before: Task[task2/node2]}'
    end
  end

  context '#concurrency' do

    context 'concurrency is not defined' do
      it 'concurrency is NOT present' do
        is_expected.not_to be_concurrency_present
      end

      it 'concurrency is available' do
        is_expected.to be_concurrency_available
      end

      it 'will not try to change the current concurrency when the status of the task changes' do
        subject.status = :running
        expect(cluster.task_concurrency[subject.name].current).to eq 0
        subject.status = :successful
        expect(cluster.task_concurrency[subject.name].current).to eq 0
      end

      it 'ready task is counted as a ready task' do
        subject.status == :ready
        is_expected.to be_ready
      end
    end

    context 'defined, but maximum is not set' do
      before(:each) do
        cluster.task_concurrency.create 'task1'
      end

      it 'concurrency is NOT present' do
        is_expected.not_to be_concurrency_present
      end

      it 'concurrency is available' do
        is_expected.to be_concurrency_available
      end

      it 'will not try to change the current concurrency when the status of the task changes' do
        subject.status = :running
        expect(cluster.task_concurrency[subject.name].current).to eq 0
        subject.status = :successful
        expect(cluster.task_concurrency[subject.name].current).to eq 0
      end

      it 'ready task is counted as a ready task' do
        subject.status == :ready
        is_expected.to be_ready
      end
    end

    context 'maximum is set and active' do
      before(:each) do
        cluster.task_concurrency['task1'].maximum = 2
        cluster.task_concurrency['task1'].current = 1
      end

      it 'concurrency is present' do
        is_expected.to be_concurrency_present
      end

      it 'concurrency is available' do
        is_expected.to be_concurrency_available
      end

      it 'can change the current concurrency when the status of the task changes' do
        subject.status = :running
        expect(cluster.task_concurrency[subject.name].current).to eq 2
        subject.status = :successful
        expect(cluster.task_concurrency[subject.name].current).to eq 1
      end

      it 'ready task is counted as a ready task' do
        subject.status == :ready
        is_expected.to be_ready
      end
    end

    context 'maximum is set and not active' do
      before(:each) do
        cluster.task_concurrency['task1'].maximum = 1
        cluster.task_concurrency['task1'].current = 2
      end

      it 'concurrency is present' do
        is_expected.to be_concurrency_present
      end

      it 'concurrency is NOT available' do
        is_expected.not_to be_concurrency_available
      end

      it 'can change the current concurrency when the status of the task changes' do
        subject.status = :running
        expect(cluster.task_concurrency[subject.name].current).to eq 3
        subject.status = :successful
        expect(cluster.task_concurrency[subject.name].current).to eq 2
      end

      it 'ready task is NOT counted as a ready task' do
        subject.status == :ready
        is_expected.not_to be_ready
      end
    end
  end

  context '#run' do
    it 'can run the task on the node' do
      node1.expects(:run).with task1
      task1.run
    end

  end

end

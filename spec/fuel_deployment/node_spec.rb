require 'spec_helper'

describe Deployment::Node do

  let(:node1) do
    Deployment::Node.new 'node1'
  end

  subject { node1 }

  let(:task1) do
    Deployment::Task.new 'task1', node1
  end

  context '#attributes' do
    it 'should have a name' do
      expect(subject.name).to eq 'node1'
    end

    it 'should have a status' do
      expect(subject.status).to eq :online
    end

    it 'should have a task' do
      expect(subject.task).to be_nil
    end

    it 'should have a graph' do
      expect(subject.graph).to be_a Deployment::Graph
    end

    it 'should have an id' do
      expect(subject.id).to eq 'node1'
    end

    it 'should have critical' do
      expect(subject.critical).to eq false
      expect(subject.critical?).to eq false
    end

    it 'can set critical' do
      subject.critical = true
      expect(subject.critical?).to eq true
      subject.critical = nil
      expect(subject.critical?).to eq false
      subject.set_critical
      expect(subject.critical?).to eq true
      subject.set_normal
      expect(subject.critical?).to eq false
      subject.critical = 'yes'
      expect(subject.critical?).to eq true
    end

    it 'can set a name' do
      subject.name = 'node2'
      expect(subject.name).to eq 'node2'
      subject.name = 1
      expect(subject.name).to eq '1'
    end

    it 'can set a status' do
      subject.status = :busy
      expect(subject.status).to eq :busy
      subject.status = 'offline'
      expect(subject.status).to eq :offline
    end

    it 'can set only a valid status' do
      expect do
        subject.status = :provisioned
      end.to raise_exception Deployment::InvalidArgument, /Invalid node status/
    end

    it 'can use dynamic status set methods' do
      subject.set_status_busy
      expect(subject.status).to eq :busy
    end

    it 'can set a task' do
      subject.add_task task1
      subject.task = task1
      expect(subject.task).to eq task1
      subject.task = nil
      expect(subject.task).to be_nil
    end

    it 'can set task only if it is in the graph' do
      expect do
        subject.task = task1
      end.to raise_exception Deployment::InvalidArgument, /not found in the graph/
    end

    it 'can set an id' do
      subject.id = 2
      expect(subject.id).to eq 2
    end

    it 'will not set task to an invalid object' do
      expect do
        subject.task = 'task1'
      end.to raise_exception Deployment::InvalidArgument, /should be a task/
    end

    it 'can set a graph' do
      old_graph = subject.graph
      new_graph = Deployment::Graph.new subject
      subject.graph = new_graph
      expect(new_graph).not_to eq old_graph
    end

    it 'can create a new graph' do
      old_graph = subject.graph
      subject.create_new_graph
      expect(subject.graph).not_to eq old_graph
    end

    it 'will not set graph to an invalid object' do
      expect do
        subject.graph = 'new_graph'
      end.to raise_exception Deployment::InvalidArgument, /should be a graph/
    end

    it 'can iterate through graph tasks' do
      subject.graph.task_add task1
      expect(subject.each.to_a).to eq [task1]
    end
  end

  context '#inspection' do

    it 'can to_s' do
      expect(subject.to_s).to eq 'Node[node1]'
      subject.id = 1
      expect(subject.to_s).to eq 'Node[1/node1]'
    end

    it 'can inspect' do
      expect(subject.inspect).to eq 'Node[node1]{Status: online Tasks: 0/0}'
      subject.status = :offline
      expect(subject.inspect).to eq 'Node[node1]{Status: offline Tasks: 0/0}'
      subject.add_task task1
      subject.task = task1
      expect(subject.inspect).to eq 'Node[node1]{Status: offline Tasks: 0/1 CurrentTask: task1}'
    end
  end

  context '#run' do
    it 'can run a task' do
      expect(subject).to respond_to :run
    end

    it 'can poll node status' do
      expect(subject).to respond_to :poll
    end
  end
end

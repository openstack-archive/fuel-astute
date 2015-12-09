require 'spec_helper'

describe Deployment::Node do

  let(:node1) do
    Deployment::Node.new 'node1'
  end

  let(:node2) do
    Deployment::Node.new 'node2'
  end

  let(:task1_1) do
    Deployment::Task.new 'task1', node1
  end

  let(:task1_2) do
    Deployment::Task.new 'task2', node1
  end

  let(:task1_3) do
    Deployment::Task.new 'task3', node1
  end

  let(:task1_4) do
    Deployment::Task.new 'task4', node1
  end

  let(:task2_1) do
    Deployment::Task.new 'task1', node2
  end

  let(:task2_2) do
    Deployment::Task.new 'task2', node2
  end

  let(:process) do
    node1.graph.add_task task1_1
    node1.graph.add_task task1_2
    node2.graph.add_task task2_1
    node2.graph.add_task task2_2
    process = Deployment::Process[node1, node2]
    process.id = 1
    process
  end

  subject { process }

  context '#attributes' do
    it 'have an id' do
      expect(subject.id).to eq 1
    end

    it 'can set an id' do
      subject.id = 2
      expect(subject.id).to eq 2
    end

    it 'have nodes' do
      expect(subject.nodes).to eq [node1, node2]
    end

    it 'can set nodes' do
      subject.nodes = [node1]
      expect(subject.nodes).to eq [node1]
    end

    it 'will set nodes only to the valid object' do
      expect do
        subject.nodes = 'node1'
      end.to raise_exception Deployment::InvalidArgument, /should be an array/
      expect do
        subject.nodes = ['node1']
      end.to raise_exception Deployment::InvalidArgument, /contain only Node/
    end
  end

  context '#nodes processing' do
    it 'can iterate through all nodes' do
      expect(subject.each_node.to_a).to eq [node1, node2]
    end

    it 'can iterate through all tasks' do
      expect(subject.each_task.to_a).to eq [task1_1, task1_2, task2_1, task2_2]
    end

    it 'can iterate through all ready tasks' do
      task1_2.after task1_1
      task2_1.after task1_2
      task2_2.after task2_1
      expect(subject.each_ready_task.to_a).to eq [task1_1]
    end

    it 'can check if all nodes are finished' do
      task1_1.status = :successful
      task1_2.status = :failed
      task2_1.status = :successful
      task2_2.status = :pending
      expect(subject.all_nodes_are_finished?).to eq false
      task2_2.status = :successful
      expect(subject.all_nodes_are_finished?).to eq true
    end

    it 'can check if all nodes are successful' do
      task1_1.status = :successful
      task1_2.status = :pending
      task2_1.status = :successful
      task2_2.status = :successful
      expect(subject.all_nodes_are_successful?).to eq false
      task1_2.status = :successful
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
      expect(subject.tasks_total_count).to eq 4
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
      expect(subject.tasks_pending_count).to eq 2
    end
  end

  context '#dfs' do
    context '#no loop' do
      let(:process) do
        task1_2.after task1_1
        task1_3.after task1_1
        task1_4.after task1_2
        task1_4.after task1_3
        node1.add_task task1_1
        node1.add_task task1_2
        node1.add_task task1_3
        node1.add_task task1_4
        process = Deployment::Process[node1]
        process.id = 'no_loop'
        process
      end

      it 'can walk forward' do
        process
        visited = task1_1.dfs_forward.to_a
        expect(visited).to eq [task1_1, task1_2, task1_4, task1_3, task1_4]
      end

      it 'can walk backward' do
        process
        visited = task1_4.dfs_backward.to_a
        expect(visited).to eq [task1_4, task1_2, task1_1, task1_3, task1_1]
      end

      it 'can topology sort' do
        expect(process.topology_sort).to eq [task1_1, task1_3, task1_2, task1_4]
      end

      it 'can check if there is no loop' do
        expect(process.has_loop?).to eq false
      end
    end

    context '#has loop' do
      let(:process) do
        task1_2.after task1_1
        task1_3.after task1_2
        task1_4.after task1_3
        task1_1.after task1_4
        node1.add_task task1_1
        node1.add_task task1_2
        node1.add_task task1_3
        node1.add_task task1_4
        process = Deployment::Process[node1]
        process.id = 'has_loop'
        process
      end

      it 'can walk forward' do
        message = 'Task[task1/node1]: Loop detected! Path: Task[task1/node1], Task[task2/node1], Task[task3/node1], Task[task4/node1], Task[task1/node1]'
        process
        expect do
          task1_1.dfs_forward.to_a
        end.to raise_error Deployment::LoopDetected, message
      end

      it 'can walk backward' do
        message = 'Task[task1/node1]: Loop detected! Path: Task[task1/node1], Task[task4/node1], Task[task3/node1], Task[task2/node1], Task[task1/node1]'
        process
        expect do
          task1_1.dfs_backward.to_a
        end.to raise_error Deployment::LoopDetected, message
      end

      it 'can topology sort' do
        message = 'Process[has_loop]: Loop detected! Path: Task[task1/node1], Task[task2/node1], Task[task3/node1], Task[task4/node1], Task[task1/node1]'
        expect do
          process.topology_sort
        end.to raise_error Deployment::LoopDetected, message
      end

      it 'can check if there is no loop' do
        expect(process.has_loop?).to eq true
      end
    end
  end

  context '#inspection' do
    it 'can to_s' do
      expect(subject.to_s).to eq 'Process[1]'
    end

    it 'can inspect' do
      expect(subject.inspect).to eq 'Process[1]{Tasks: 0/4 Nodes: node1, node2}'
    end

    it 'can generate dot graph' do
      graph = <<-eof
digraph test_graph {
node[ style = "filled, solid"];
  "Task[task1/node1]" [label = "Task[task1/node1]"], fillcolor = "yellow"];
  "Task[task2/node1]" [label = "Task[task2/node1]"], fillcolor = "white"];
  "Task[task3/node1]" [label = "Task[task3/node1]"], fillcolor = "white"];
  "Task[task4/node1]" [label = "Task[task4/node1]"], fillcolor = "white"];

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
      node1.add_task task1_1
      node1.add_task task1_2
      node1.add_task task1_3
      node1.add_task task1_4
      process = Deployment::Process[node1]
      process.id = 'test_graph'
      expect(process.to_dot).to eq graph
    end
  end
end

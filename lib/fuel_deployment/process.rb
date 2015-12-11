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

require 'erb'
require 'open3'

module Deployment

  # The Process object controls the deployment flow.
  # It loops through the nodes and runs tasks on then
  # when the node is ready and the task is available.
  #
  # attr [Object] id Misc identifier of this process
  class Process

    # @param [Array<Deployment::Node>] nodes The array of nodes to deploy
    def initialize(*nodes)
      self.nodes = nodes.flatten
      @id = nil
    end

    include Enumerable
    include Deployment::Log

    attr_reader :nodes
    attr_accessor :id
    attr_accessor :plot_number

    # Create the Process object with these nodes
    # @param [Array<Deployment::Node>] nodes The array of nodes to deploy
    def self.[](*nodes)
      self.new(*nodes)
    end

    # Set a new nodes array
    # @raise Deployment::InvalidArgument If this is not an array or it consists not only of Nodes
    # @param [Array<Deployment::Node>] nodes The array of nodes to deploy
    # @return Deployment::Node
    def nodes=(nodes)
      raise Deployment::InvalidArgument.new self, 'Nodes should be an array!', nodes unless nodes.is_a? Array
      raise Deployment::InvalidArgument.new self, 'Nodes should contain only Node objects!', nodes unless nodes.all? { |n| n.is_a? Deployment::Node }
      @nodes = nodes
    end

    # Iterates through all nodes
    # @yield Deployment::Node
    def each_node(&block)
      nodes.each(&block)
    end
    alias :each :each_node

    # Iterates through all the tasks on all nodes
    # @yield Deployment::Task
    def each_task
      return to_enum(:each_task) unless block_given?
      each_node do |node|
        node.each_task do |task|
          yield task
        end
      end
    end

    # Iterates through the task that are ready to be run
    # @yield Deployment::Task
    def each_ready_task
      return to_enum(:each_ready_task) unless block_given?
      each_task do |task|
        yield task if task.ready?
      end
    end

    # Check if graphs have a closed loop
    # @return [true, false]
    def has_loop?
      begin
        topology_sort
        false
      rescue Deployment::LoopDetected
        true
      end
    end

    # Topology sort all tasks in all graphs
    # Tarjan's algorithm
    # @return [Array<Deployment::Task>]
    # @raise
    def topology_sort
      topology = []
      permanently_visited = Set.new
      temporary_visited = []
      loop do
        next_task = each_task.find do |task|
          not (permanently_visited.include? task or temporary_visited.include? task)
        end
        return topology unless next_task
        visit next_task, topology, permanently_visited, temporary_visited
      end
      topology
    end

    # Tarjan's Algorithm visit function
    # @return [Array<Deployment::Task>]
    # @raise Deployment::LoopDetected If a loop is detected in the graph
    # These parameters are carried through the recursion calls:
    # @param [Array<Deployment::Task>] topology A list of topologically sorted tasks
    # @param [Set<Deployment::Task>] permanently_visited Set of permanently visited tasks
    # @param [Array<Deployment::Task>] temporary_visited List of temporary visited tasks
    def visit(task, topology = [], permanently_visited = Set.new, temporary_visited = [])
      if temporary_visited.include? task
        # This node have already been visited in this small iteration and
        # it means that there is a loop.
        temporary_visited << task
        raise Deployment::LoopDetected.new self, 'Loop detected!', temporary_visited
      end
      if permanently_visited.include? task
        # We have already checked this node for loops in
        # its forward dependencies. Skip it.
        return
      end
      # Start a small iteration over this node's forward dependencies
      # add this node to the last iteration visit list and run recursion
      # on the forward dependencies
      temporary_visited << task
      task.each_forward_dependency do |forward_task|
        visit forward_task, topology, permanently_visited, temporary_visited
      end
      # Small iteration have completed without loops.
      # We add this node to the list of permanently marked nodes and
      # remove in from the temporary marked nodes list.
      permanently_visited.add task
      temporary_visited.delete task
      # Insert this node to the head of topology sort list and return it.
      topology.insert 0, task
    end

    # Process a single node when it's visited.
    # First, poll the node's status nad leave it the node is not ready.
    # Then try to get a next task from the node and run it, or leave, if
    # there is none available.
    # @param [Deployment::Node] node
    # @return [void]
    def process_node(node)
      debug "Process node: #{node}"
      hook 'pre_node', node
      node.poll
      return unless node.online?
      ready_task = node.ready_task
      return unless ready_task
      ready_task.run
      hook 'post_node', node
    end

    # Run a hook method is this method is defined
    # @param [String, Symbol] name Hook name
    # @param [Object] args Hook arguments
    def hook(name, *args)
      name = ('hook_' + name.to_s).to_sym
      send name, *args if respond_to? name
    end

    # Loops once through all nodes and processes each one
    # @return [void]
    def process_all_nodes
      debug 'Start processing all nodes'
      hook 'pre_all'
      each_node do |node|
        process_node node
      end
      hook 'post_all'
    end

    # Run this deployment process.
    # It will loop through all nodes running task
    # until the deployment will be considered finished.
    # Deployment is finished if all the nodes have all tasks finished
    # successfully, or finished with other statuses.
    # Actually, it's enough to check only for finished nodes.
    # @return [true, false]
    def run
      ready_nodes = each_ready_task.to_a.join ', '
      info "Starting the deployment process from tasks: #{ready_nodes}"
      topology_sort
      hook 'pre_run'
      result = loop do
        if all_nodes_are_successful?
          status = 'All nodes are deployed successfully. Stopping the deployment process!'
          result = {
              :success => true,
              :status => status,
          }
          info result[:status]
          break result
        end
        if has_failed_critical_nodes?
          failed_names = failed_critical_nodes.map { |n| n.name }.join ', '
          status =  "Critical nodes failed: #{failed_names}. Stopping the deployment process!"
          result = {
              :success => false,
              :status => status,
              :failed_nodes => failed_critical_nodes,
              :failed_tasks => failed_tasks,
          }
          break result
        end
        if all_nodes_are_finished?
          status = 'All nodes are finished. Stopping the deployment process!'
          result = {
              :success => false,
              :status => status,
              :failed_nodes => failed_nodes,
              :failed_tasks => failed_tasks,
          }
          break result
        end
        # run loop over all nodes
        process_all_nodes
      end
      hook 'post_run', result
      result
    end

    # Get the list of critical nodes
    # @return [Array<Deployment::Node>]
    def critical_nodes
      select do |node|
        node.critical?
      end
    end

    # Get the list of critical nodes that have failed
    # @return [Array<Deployment::Node>]
    def failed_critical_nodes
      critical_nodes.select do |node|
        node.failed?
      end
    end

    # Check if there are some critical nodes
    # that have failed
    # @return [true, false]
    def has_failed_critical_nodes?
      failed_critical_nodes.any?
    end

    # Get the list of the failed nodes
    # @return [Array<Deployment::Node>]
    def failed_nodes
      select do |node|
        node.failed?
      end
    end

    # Get the list of the failed nodes
    # @return [Array<Deployment::Node>]
    def failed_tasks
      each_task.select do |task|
        task.status == :failed
      end
    end

    # Check if some nodes are failed
    # @return [true, false]
    def has_failed_nodes?
      failed_nodes.any?
    end

    # Check if all nodes are finished
    # @return [true, false]
    def all_nodes_are_finished?
      all? do |node|
        node.finished?
      end
    end

    # Check if all nodes are successful
    # @return [true, false]
    def all_nodes_are_successful?
      all? do |node|
        node.successful?
      end
    end

    # Count the total task number on all nodes
    # @return [Integer]
    def tasks_total_count
      inject(0) do |sum, node|
        sum + node.graph.tasks_total_count
      end
    end

    # Count the total number of the failed tasks
    # @return [Integer]
    def tasks_failed_count
      inject(0) do |sum, node|
        sum + node.graph.tasks_failed_count
      end
    end

    # Count the total number of the successful tasks
    # @return [Integer]
    def tasks_successful_count
      inject(0) do |sum, node|
        sum + node.graph.tasks_successful_count
      end
    end

    # Count the total number of the finished tasks
    # @return [Integer]
    def tasks_finished_count
      inject(0) do |sum, node|
        sum + node.graph.tasks_finished_count
      end
    end

    # Count the total number of the pending tasks
    # @return [Integer]
    def tasks_pending_count
      inject(0) do |sum, node|
        sum + node.graph.tasks_pending_count
      end
    end

    # Generate the deployment graph representation
    # in the DOT language
    # @return [String]
    def to_dot
      template = <<-eos
digraph "<%= id || graph %>" {
node[ style = "filled, solid"];
<% each_task do |task| -%>
  "<%= task %>" [label = "<%= task %>", fillcolor = "<%= task.color %>"];
<% end -%>

<% each_task do |task| -%>
<% task.each_forward_dependency do |forward_task| -%>
  "<%= task %>" -> "<%= forward_task %>";
<% end -%>
<% end -%>
}
      eos
      ERB.new(template, nil, '-').result(binding)
    end

    # Plot the graph using the 'dot' binary
    # @param [Integer,String] suffix File name index or suffix.
    # Will use incrementing value unless provided.
    # @param [String] type The type of image produced
    # @return [true, false] Successful?
    def plot(suffix=nil, type='png')
      unless suffix
        @plot_number = 0 unless @plot_number
        suffix = @plot_number
        @plot_number += 1
      end
      if suffix.is_a? Integer
        suffix = suffix.to_s.rjust 5, '0'
      end
      graph_name = id || 'graph'
      file_name = "#{graph_name}-#{suffix}.#{type}"
      command = "dot -T #{type} > #{file_name}"
      Open3.popen2e(command) do |stdin, out, process|
        stdin.puts to_dot
        stdin.close
        output = out.read
        debug output unless output.empty?
        process.value.exitstatus == 0
      end
    end

    # @return [String]
    def to_s
      "Process[#{id}]"
    end

    # @return [String]
    def inspect
      message = "#{self}"
      message += "{Tasks: #{tasks_finished_count}/#{tasks_total_count} Nodes: #{map { |node| node.name }.join ', '}}" if nodes.any?
      message
    end

  end
end

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

  # The Cluster object contains nodes and controls the deployment flow.
  # It loops through the nodes and runs tasks on then
  # when the node is ready and the task is available.
  #
  # attr [Object] id Misc identifier of this process
  # @attr_reader [Hash<Symbol => Deployment::Node>] nodes The nodes of this cluster
  # @attr [Deployment::Concurrency::Counter] node_concurrency Controls the
  # maximum number of nodes running tasks at the same time
  class Cluster
    # @param [String] id Cluster name
    def initialize(id=nil)
      @nodes = {}
      @id = id
      @node_concurrency = Deployment::Concurrency::Counter.new
      @task_concurrency = Deployment::Concurrency::Group.new
      @emergency_brake = false
      @fault_tolerance_groups = []
      @subgraphs = []
      @dot_task_filter = nil
      @dot_node_filter = nil
      @dot_plot_number = 0
    end

    include Enumerable
    include Deployment::Log

    attr_accessor :id
    attr_accessor :gracefully_stop_mark
    attr_accessor :subgraphs
    attr_reader :emergency_brake
    attr_reader :nodes
    attr_reader :node_concurrency
    attr_reader :task_concurrency
    attr_reader :fault_tolerance_groups
    attr_accessor :dot_node_filter
    attr_accessor :dot_task_filter
    attr_accessor :dot_plot_number

    # Add an existing node object to the cluster
    # @param [Deployment::Node] node a new node object
    # @raise [Deployment::InvalidArgument] If the object is not a node
    # @return [Deployment::Node]
    def node_add(node)
      raise Deployment::InvalidArgument.new self, 'Cluster can add only nodes!', node unless node.is_a? Deployment::Node
      return node_get node if node_present? node
      unless node.cluster == self
        node.cluster.node_remove node if node.cluster
      end
      nodes.store prepare_key(node), node
      node.cluster = self
      node
    end
    alias :add_node :node_add

    # Create a new node object by its name and add it to the cluster.
    # Or, if the node already exists, return the existing node object.
    # @param [String, Symbol] node The name of the new node
    # @param [Class] node_class Optional custom node class
    # @return [Deployment::Node]
    def node_create(node, node_class=Deployment::Node)
      if node_present? node
        node = node_get node
      elsif node.is_a? Deployment::Node
        node = node_add node
      else
        node = node_class.new node, self
        node = node_add node unless node_present? node
      end
      node
    end
    alias :create_node :node_create
    alias :new_node :node_create
    alias :node_new :node_create

    # Remove a node from this cluster
    # @param [Deployment::Node, String, Symbol] node
    # @return [void]
    def node_remove(node)
      return unless node_present? node
      nodes.delete prepare_key(node)
    end
    alias :remove_node :node_remove

    # Retrieve a node object from the cluster
    # @param [String, Symbol] node The name of the node to retrieve
    # @return [Deployment::Node, nil]
    def node_get(node)
      nodes.fetch prepare_key(node), nil
    end
    alias :get_node :node_get
    alias :[] :node_get

    def node_present?(node)
      nodes.key? prepare_key(node)
    end
    alias :has_node? :node_present?
    alias :key? :node_present?

    # Prepare the hash key from the node
    # @param [Deployment::Task,String,Symbol] node
    def prepare_key(node)
      node = node.name if node.is_a? Deployment::Node
      node.to_s.to_sym
    end

    # Iterates through all cluster nodes
    # @yield Deployment::Node
    def each_node(&block)
      nodes.each_value(&block)
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

    # Sets up subgraphs for execution
    # e.g. user might want to run only a subset
    # of tasks: in this case he sends
    # an array of subgraphs to be executed.
    # Each array consists of starting vertices
    # and ending vertices. These vertices are then
    # traversed forward or backward

    def setup_start_end
      require 'pry-byebug'
      cluster_tasks_set = Set.new each_task
      tasks_to_include = Set.new
      def setup_start_end_piece(subgraph, cluster)
        start_tasks = Set.new
        end_tasks = Set.new
        binding.pry
        subgraph.fetch('start', []).each do |task|
          task.dfs_forward.each do |fw|
            start_tasks.add fw
          end
        end
        subgraph.fetch('end', []).each do |task|
          task.dfs_backward.each do |bw|
            end_tasks.add bw
          end
        end
        start_tasks = start_tasks.empty? ? cluster : start_tasks
        end_tasks = end_tasks.empty? ? cluster : end_tasks
        start_tasks & end_tasks
      end
      self.subgraphs.each do |subgraph|
        setup_start_end_piece(subgraph, cluster_tasks_set).each do |piece|
          tasks_to_include.add piece
        end
      end

      to_skip_tasks = cluster_tasks_set - tasks_to_include
      to_skip_tasks.each do |task|
        task.skip!
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
      return if node.skipped?
      node.poll
      hook 'internal_post_node_poll', node
      hook 'post_node_poll', node
      return unless node.ready?
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
      info "Starting the deployment process. Starting tasks: #{ready_nodes}"
      hook 'internal_pre_run'
      hook 'pre_run'
      topology_sort
      result = loop do
        if all_nodes_are_successful?
          status = 'All nodes are deployed successfully. '\
                   'Stopping the deployment process!'
          result = {
              :success => true,
              :status => status,
          }
          break result
        end
        gracefully_stop! if has_failed_critical_nodes?

        if all_nodes_are_finished?
          status = "All nodes are finished. Failed tasks: "\
                  "#{failed_tasks.join ', '} Stopping the "\
                  "deployment process!"
          result = if has_failed_critical_nodes?
            {
              :success => false,
              :status => status,
              :failed_nodes => failed_nodes,
              :skipped_nodes => skipped_nodes,
              :failed_tasks => failed_tasks
            }
          else
            {
              :success => true,
              :status => status,
              :failed_nodes => failed_nodes,
              :skipped_nodes => skipped_nodes,
              :failed_tasks => failed_tasks
            }
          end
          break result
        end
        # run loop over all nodes
        process_all_nodes
      end
      info result[:status]
      hook 'post_run', result
      result
    end
    alias :deploy :run

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
        node.failed? && !node.skipped?
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
        node.failed? && !node.skipped?
      end
    end

    def skipped_nodes
      select do |node|
        node.skipped?
      end
    end


    # Get the list of the failed nodes
    # @return [Array<Deployment::Task>]
    def failed_tasks
      each_task.select do |task|
        task.status == :failed
      end
    end

    # Get the list of tasks that have no forward dependencies
    # They are the ending points of the deployment.
    # @return [Array<Deployment::Task>]
    def ending_tasks
      each_task.reject do |task|
        task.dependency_forward_any?
      end
    end

    # Get the list of tasks that have no backward dependencies
    # They are the starting points of the deployment.
    # @return [Array<Deployment::Task>]
    def starting_tasks
      each_task.reject do |task|
        task.dependency_backward_any?
      end
    end

    # Get the list of tasks that have no dependencies at all.
    # They are most likely have been lost for some reason.
    # @return [Array<Deployment::Task>]
    def orphan_tasks
      each_task.reject do |task|
        task.dependency_backward_any? or task.dependency_forward_any?
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
digraph "<%= id || 'graph' %>" {
  node[ style = "filled, solid"];
<% each_task do |task| -%>
<% next unless task.name =~ dot_task_filter if dot_task_filter -%>
<% next unless task.node.name =~ dot_node_filter if dot_node_filter and task.node -%>
  "<%= task %>" [label = "<%= task %>", fillcolor = "<%= task.color %>"];
<% end -%>

<% each_task do |task| -%>
<% task.each_forward_dependency do |forward_task| -%>
<% next unless task.name =~ dot_task_filter if dot_task_filter -%>
<% next unless task.node.name =~ dot_node_filter if dot_node_filter and task.node -%>
<% next unless forward_task.name =~ dot_task_filter if dot_task_filter -%>
<% next unless forward_task.node.name =~ dot_node_filter if dot_node_filter and forward_task.node -%>
  "<%= task %>" -> "<%= forward_task %>";
<% end -%>
<% end -%>
}
      eos
      ERB.new(template, nil, '-').result(binding)
    end

    # Plot the graph using the 'dot' binary
    # Will use incrementing value unless provided.
    # @param [Hash] options
    # Will use autogenerated name in the current folder unless provided
    # @return [true, false] Successful?
    def make_image(options={})
      file = options.fetch :file, nil
      suffix = options.fetch :suffix, nil
      type = options.fetch :type, 'svg'

      unless file
        unless suffix
          suffix = dot_plot_number
          self.dot_plot_number += 1
        end
        if suffix.is_a? Integer
          suffix = suffix.to_s.rjust 5, '0'
        end
        graph_name = id || 'graph'
        file = "#{graph_name}-#{suffix}.#{type}"
      end
      info "Writing the graph image: '#{suffix}' to the file: '#{file}'"
      command = ['dot', '-T', type, '-o', file]
      Open3.popen2e(*command) do |stdin, out, process|
        stdin.puts to_dot
        stdin.close
        output = out.read
        debug output unless output.empty?
        process.value.exitstatus == 0
      end
    end

    # Get the array of this cluster's node names.
    # They can be used for reference.
    # @return [Array<String>]
    def node_names
      map do |node|
        node.name
      end.sort
    end

    def stop_condition(&block)
      self.gracefully_stop_mark = block
    end

    def hook_internal_post_node_poll(*args)
      gracefully_stop(args[0])
      validate_fault_tolerance(args[0])
    end

    def hook_internal_pre_run(*args)
      return unless has_failed_nodes?
      failed_nodes.each { |node| validate_fault_tolerance(node) }
    end

    # Check if the deployment process should stop
    # @return [true, false]
    def gracefully_stop?
      return true if @emergency_brake
      if gracefully_stop_mark && gracefully_stop_mark.call
        info "Stop deployment by stop condition (external reason)"
        @emergency_brake = true
      end
      @emergency_brake
    end

    def gracefully_stop(node)
      if gracefully_stop? && node.ready?
        node.set_status_skipped
        hook 'post_gracefully_stop', node
      end
    end

    def gracefully_stop!
      return if @emergency_brake

      info "Stop deployment by internal reason"
      @emergency_brake = true
    end

    def fault_tolerance_groups=(groups=[])
      @fault_tolerance_groups = groups.select { |group| group['node_ids'].present? }
      @fault_tolerance_groups.each { |group| group['failed_node_ids'] = [] }
      debug "Setup fault tolerance groups: #{@fault_tolerance_groups}"
    end

    def validate_fault_tolerance(node)
      return if gracefully_stop?

      if node.failed?
        count_tolerance_fail(node)
        gracefully_stop! if fault_tolerance_excess?
      end
    end

    def count_tolerance_fail(node)
      fault_tolerance_groups.select do |g|
        g['node_ids'].include?(node.name)
      end.each do |group|
        debug "Count failed node #{node.name} for group #{group['name']}"
        group['fault_tolerance'] -= 1
        group['node_ids'].delete(node.name)
        group['failed_node_ids'] << node.name
      end
    end

    def fault_tolerance_excess?
      is_failed = fault_tolerance_groups.select { |group| group['fault_tolerance'] < 0 }
      return false if is_failed.empty?

      warn "Fault tolerance exceeded the stop conditions #{is_failed}"
      true
    end

    # @return [String]
    def to_s
      "Cluster[#{id}]"
    end

    # @return [String]
    def inspect
      message = "#{self}"
      message += "{Tasks: #{tasks_finished_count}/#{tasks_total_count} Nodes: #{node_names.join ', '}}" if nodes.any?
      message
    end

  end
end

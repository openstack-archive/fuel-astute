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

module Deployment

  # The Node class should work with a deployed nodes
  # it should be able to somehow run tasks on them and
  # query their status. It should also manage it's status
  # attribute and the status of the currently running task.
  # A Node has a Graph object assigned and can run all methods
  # of the Graph object.
  #
  # @attr [Symbol] status The node's status
  # @attr [String] name The node's name
  # @attr [Deployment::Task] task The currently running task of this node
  # @attr [Deploymnet::Cluster] cluster The cluster this node is assigned to
  # @attr [Deployment::Graph] graph The Graph assigned to this node
  # @attr [Numeric, String] id Misc id that can be used by this node
  # @attr [true, false] critical This node is critical for the deployment
  # and the deployment is considered failed if this node is failed
  class Node
    # A node can have one of these statuses
    ALLOWED_STATUSES = [:online, :busy, :offline, :failed, :successful, :skipped]
    # A node is considered finished with one of these statuses
    FINISHED_STATUSES = [:failed, :successful, :skipped]

    # @param [String, Symbol] name
    # @param [Deployment::Cluster] cluster
    # @param [Object] id
    def initialize(name, cluster, id = nil)
      @name = name
      @status = :online
      @task = nil
      @critical = false
      @id = id || self.name
      self.cluster = cluster
      cluster.node_add self
      create_new_graph
    end

    include Enumerable
    include Deployment::Log

    attr_reader :status
    attr_reader :name
    attr_reader :task
    attr_reader :cluster
    alias :current_task :task
    attr_reader :graph
    attr_accessor :id
    attr_reader :critical
    alias :critical? :critical

    # Set a new status of this node
    # @param [Symbol, String] value
    # @raise [Deployment::InvalidArgument] if the status is not valid
    # @return [Symbol]
    def status=(value)
      value = value.to_sym
      raise Deployment::InvalidArgument.new self, 'Invalid node status!', value unless ALLOWED_STATUSES.include? value
      status_changes_concurrency @status, value
      @status = value
    end

    # Set the critical property of this node
    # @param [true, false] value
    # @return [true, false]
    def critical=(value)
      @critical = !!value
    end

    # Set this node to be a critical node
    # @return [true]
    def set_critical
      self.critical = true
    end

    # Set this node to be a normal node
    # @return [false]
    def set_normal
      self.critical = false
    end

    # Set this node's Cluster Object
    # @param [Deployment::Cluster] cluster The new cluster object
    # @raise [Deployment::InvalidArgument] if the object is not a Node
    # @return [Deployment::Node]
    def cluster=(cluster)
      raise Deployment::InvalidArgument.new self, 'Not a cluster used instead of the cluster object!', cluster unless cluster.is_a? Deployment::Cluster
      @cluster = cluster
    end

    # Get the current node concurrency value
    # or perform an action with this value.
    # @param [Symbol] action
    # @option action [Symbol] :inc Increase the value
    # @option action [Symbol] :dec Decrease the value
    # @option action [Symbol] :reset Set the value to zero
    # @option action [Symbol] :set Manually set the value
    # @param [Integer] value Manually set to this value
    # @return [Integer]
    def self.current_concurrency(action = :get, value = nil)
      @current_concurrency = 0 unless @current_concurrency
      return @current_concurrency unless action
      if action == :inc
        @current_concurrency += 1
      elsif action == :dec
        @current_concurrency -= 1
      elsif action == :zero
        @current_concurrency = 0
      elsif action == :set
        begin
          @current_concurrency = Integer(value)
        rescue TypeError, ArgumentError
          raise Deployment::InvalidArgument.new self, 'Current concurrency should be an integer number!', value
        end
      end
      @current_concurrency = 0 if @current_concurrency < 0
      @current_concurrency
    end

    # Get or set the maximum node concurrency value.
    # Value is set if the second argument is provided.
    # @param [Integer, nil] value
    # @return [Integer]
    def self.maximum_concurrency(value = nil)
      @maximum_concurrency = 0 unless @maximum_concurrency
      return @maximum_concurrency unless value
      begin
        @maximum_concurrency = Integer(value)
      rescue TypeError, ArgumentError
        raise Deployment::InvalidArgument.new self, 'Maximum concurrency should be an integer number!', value
      end
      @maximum_concurrency
    end

    # Get the maximum node concurrency
    # @return [Integer]
    def maximum_concurrency
      self.class.maximum_concurrency
    end

    # Set the maximum node concurrency
    # @param [Integer] value
    # @return [Integer]
    def maximum_concurrency=(value)
      self.class.maximum_concurrency value
    end

    # Get the current node concurrency
    # @return [Integer]
    def current_concurrency
      self.class.current_concurrency
    end

    # Increase the current node concurrency by one
    # @return [Integer]
    def current_concurrency_increase
      self.class.current_concurrency :inc
    end

    # Decrease the current node concurrency by one
    # @return [Integer]
    def current_concurrency_decrease
      self.class.current_concurrency :dec
    end

    # Reset the current node concurrency to zero
    # @return [Integer]
    def current_concurrency_zero
      self.class.current_concurrency :zero
    end

    # Manually set the node current concurrency value
    # @param [Integer] value
    # @return [Integer]
    def current_concurrency=(value)
      self.class.current_concurrency :set, value
    end

    # Check if there are node concurrency slots available
    # to run this task.
    # @return [true, false]
    def concurrency_available?
      return true unless maximum_concurrency_is_set?
      current_concurrency < maximum_concurrency
    end

    # Check if the maximum node concurrency is set
    # @return [true, false]
    def maximum_concurrency_is_set?
      maximum_concurrency > 0
    end

    # Increase or decrease the node concurrency value
    # when the node's status is changed.
    # @param [Symbol] status_from
    # @param [Symbol] status_to
    # @return [void]
    def status_changes_concurrency(status_from, status_to)
      return unless maximum_concurrency_is_set?
      if status_to == :busy
        current_concurrency_increase
        info "Increasing node concurrency to: #{current_concurrency}"
      elsif status_from == :busy
        current_concurrency_decrease
        info "Decreasing node concurrency to: #{current_concurrency}"
      end
    end

    # The node have finished all its tasks
    # or has one of finished statuses
    # @return [true, false]
    def finished?
      FINISHED_STATUSES.include? status or tasks_are_finished?
    end

    # Check if this node is ready to receive a task: it's online and
    # concurrency slots are available.
    # @return [true, false]
    def ready?
      online? and concurrency_available?
    end

    # The node is online and can accept new tasks
    # @return [true, false]
    def online?
      status == :online
    end

    # The node is busy running a task
    # @return [true, false]
    def busy?
      status == :busy
    end

    # The node is offline and cannot accept tasks
    # @return [true, false]
    def offline?
      status == :offline
    end

    # The node has several failed tasks
    # or has the failed status
    # @return [true, false]
    def failed?
      status == :failed or tasks_have_failed?
    end

    # The node has all tasks successful
    # or has the successful status
    # @return [true, false]
    def successful?
      status == :successful or tasks_are_successful?
    end

    # The node is skipped and will not get any tasks
    def skipped?
      status == :skipped
    end

    ALLOWED_STATUSES.each do |status|
      method_name = "set_status_#{status}".to_sym
      define_method(method_name) do
        self.status = status
      end
    end

    # Set the new name of this node
    # @param [String, Symbol] name
    def name=(name)
      @name = name.to_s
    end

    # Set the new current task of this node
    # @param [Deployment::Task, nil] task
    # @raise [Deployment::InvalidArgument] if the object is not a task or nil or the task is not in this graph
    # @return [Deployment::Task]
    def task=(task)
      unless task.nil?
        raise Deployment::InvalidArgument.new self, 'Task should be a task object or nil!', task unless task.is_a? Deployment::Task
        raise Deployment::InvalidArgument.new self, 'Task is not found in the graph!', task unless graph.task_present? task
      end
      @task = task
    end
    alias :current_task= :task=

    # Set a new graph object
    # @param [Deployment::Graph] graph
    # @return [Deployment::Graph]
    def graph=(graph)
      raise Deployment::InvalidArgument.new self, 'Graph should be a graph object!', graph unless graph.is_a? Deployment::Graph
      graph.node = self
      @graph = graph
    end

    # Create a new empty graph object for this node
    # @return [Deployment::Graph]
    def create_new_graph
      self.graph = Deployment::Graph.new(self)
    end

    # @return [String]
    def to_s
      return "Node[#{id}]" if id == name
      "Node[#{id}/#{name}]"
    end

    # @return [String]
    def inspect
      message = "#{self}{Status: #{status}"
      message += " Tasks: #{tasks_finished_count}/#{tasks_total_count}"
      message += " CurrentTask: #{task.name}" if task
      message + '}'
    end

    # Sends all unknown methods to the graph object
    def method_missing(method, *args, &block)
      graph.send method, *args, &block
    end

    # Run the task on this node
    # @param [Deployment::Task] task
    # @abstract Should be implemented in a subclass
    def run(task)
      debug "Run task: #{task}"
      raise Deployment::NotImplemented, 'This method is abstract and should be implemented in a subclass'
    end

    # Polls the status of the node
    # should update the node's status
    # and the status of the current task
    # @abstract Should be implemented in a subclass
    def poll
      raise Deployment::NotImplemented, 'This method is abstract and should be implemented in a subclass'
    end

  end
end

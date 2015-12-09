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
    # @param [Object] id
    def initialize(name, id = nil)
      @name = name
      @status = :online
      @task = nil
      @critical = false
      @id = id || self.name
      create_new_graph
    end

    include Enumerable
    include Deployment::Log

    attr_reader :status
    attr_reader :name
    attr_reader :task
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

    # The node have finished all its tasks
    # or has one of finished statuses
    # @return [true, false]
    def finished?
      FINISHED_STATUSES.include? status or tasks_are_finished?
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

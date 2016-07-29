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

require 'set'

module Deployment

  # The Task object represents a single deployment action.
  # It should be able to store information of it dependencies and
  # the tasks that depend on it. It should also be able to check if
  # the dependencies are ready so this task can be run or check if
  # there are some failed dependencies.
  # Task should maintain it's own status and have both name
  # and data payload attributes. Task is always assigned to a node
  # object that will be used to run it.
  #
  # @attr [String] name The task name
  # @attr [Deployment::Node] node The node object of this task
  # @attr [Symbol] status The status of this task
  # @attr_reader [Set<Deployment::Task>] backward_dependencies The Tasks required to run this task
  # @attr_reader [Set<Deployment::Task>] forward_dependencies The Tasks that require this Task to run
  # @attr [Object] data The data payload of this task
  # @attr [Integer] maximum_concurrency The maximum number of this task's instances running on the different nodes at the same time
  # @attr [Integer] current_concurrency The number of currently running task with the same name on all nodes
  class Task
    # A task can be in one of these statuses
    ALLOWED_STATUSES = [:pending, :successful, :failed, :dep_failed, :skipped, :running, :ready]
    # Task have not run yet
    NOT_RUN_STATUSES = [:pending, :ready]
    # Task is failed or dependencies have failed
    FAILED_STATUSES = [:failed, :dep_failed]
    # Task is finished without an error
    SUCCESS_STATUSES = [:successful, :skipped]
    # Task is finished, successful or not
    FINISHED_STATUSES = FAILED_STATUSES + SUCCESS_STATUSES

    # @param [String,Symbol] name The name of this task
    # @param [Deployment::Node] node The task will be assigned to this node
    # @param [Object] data The data payload. It can be any object and contain any
    # information that will be required to actually run the task.
    def initialize(name, node, data={})
      self.name = name
      @status = :pending
      @backward_dependencies = Set.new
      @forward_dependencies = Set.new
      @data = data
      self.node = node
      node.add_task self
    end

    include Enumerable
    include Deployment::Log

    attr_reader :name
    attr_reader :node
    attr_reader :status
    attr_reader :backward_dependencies
    attr_reader :forward_dependencies
    attr_accessor :data

    # Set this task's Node object
    # @param [Deployment::Node] node The new node object
    # @raise [Deployment::InvalidArgument] if the object is not a Node
    # @return [Deployment::Node]
    def node=(node)
      raise Deployment::InvalidArgument.new self, 'Not a node used instead of the task node!', node unless node.is_a? Deployment::Node
      @node = node
    end

    # Set the new task name
    # @param [String, Symbol] name
    # @return [String]
    def name=(name)
      @name = name.to_s
    end

    def skip!
      @data['type'] = 'skipped'
    end

    # Set the new task status. The task status can influence the dependency
    # status of the tasks that depend on this task then they should be reset to allow them to update
    # their status too.
    # @param [Symbol, String] value
    # @raise [Deployment::InvalidArgument] if the status is not valid
    # @return [Symbol]
    def status=(value)
      value = value.to_s.to_sym
      raise Deployment::InvalidArgument.new self, 'Invalid task status!', value unless ALLOWED_STATUSES.include? value
      status_changes_concurrency @status, value
      @status = value
      poll_forward if FINISHED_STATUSES.include? value
      value
    end

    # Check if this task has a Concurrency::Counter defined in the Group
    # identified by this task's name and it has a defined maximum value
    # @return [true,false]
    def concurrency_present?
      return false unless node.is_a? Deployment::Node
      return false unless node.cluster.is_a? Deployment::Cluster
      return false unless node.cluster.task_concurrency.is_a? Deployment::Concurrency::Group
      return false unless node.cluster.task_concurrency.key? name
      node.cluster.task_concurrency[name].maximum_set?
    end

    # Check if this task has a free concurrency slot to run
    # @return [true,false]
    def concurrency_available?
      return true unless concurrency_present?
      node.cluster.task_concurrency[name].available?
    end

    # Increase or decrease the task concurrency value
    # when the task's status is changed.
    # @param [Symbol] status_from
    # @param [Symbol] status_to
    # @return [void]
    def status_changes_concurrency(status_from, status_to)
      return unless concurrency_present?
      return if status_from == status_to
      if status_to == :running
        node.cluster.task_concurrency[name].increment
        debug "Increasing task concurrency to: #{node.cluster.task_concurrency[name].current}"
      elsif status_from == :running
        node.cluster.task_concurrency[name].decrement
        debug "Decreasing task concurrency to: #{node.cluster.task_concurrency[name].current}"
      end
    end

    ALLOWED_STATUSES.each do |status|
      method_name = "set_status_#{status}".to_sym
      define_method(method_name) do
        self.status = status
      end
    end

    # Add a new backward dependency - the task, required to run this task
    # @param [Deployment::Task] task
    # @raise [Deployment::InvalidArgument] if the task is not a Task object
    # @return [Deployment::Task]
    def dependency_backward_add(task)
      raise Deployment::InvalidArgument.new self, 'Dependency should be a task!', task unless task.is_a? Task
      return task if task == self
      backward_dependencies.add task
      task.forward_dependencies.add self
      #reset
      task
    end
    alias :requires :dependency_backward_add
    alias :depends :dependency_backward_add
    alias :after :dependency_backward_add
    alias :dependency_add :dependency_backward_add
    alias :add_dependency :dependency_backward_add

    # Add a new forward dependency - the task, that requires this task to run
    # @param [Deployment::Task] task
    # @raise [Deployment::InvalidArgument] if the task is not a Task object
    # @return [Deployment::Task]
    def dependency_forward_add(task)
      raise Deployment::InvalidArgument.new self, 'Dependency should be a task!', task unless task.is_a? Task
      return task if task == self
      forward_dependencies.add task
      task.backward_dependencies.add self
      #reset
      task
    end
    alias :is_required :dependency_forward_add
    alias :depended_on :dependency_forward_add
    alias :before :dependency_forward_add

    # remove a backward dependency of this task
    # @param [Deployment::Task] task
    # @raise [Deployment::InvalidArgument] if the task is not a Task object
    # @return [Deployment::Task]
    def dependency_backward_remove(task)
      raise Deployment::InvalidArgument.new self, 'Dependency should be a task!', task unless task.is_a? Task
      backward_dependencies.delete task
      task.forward_dependencies.delete self
      task
    end
    alias :remove_requires :dependency_backward_remove
    alias :remove_depends :dependency_backward_remove
    alias :remove_after :dependency_backward_remove
    alias :dependency_remove :dependency_backward_remove
    alias :remove_dependency :dependency_backward_remove

    # Remove a forward dependency of this task
    # @param [Deployment::Task] task
    # @raise [Deployment::InvalidArgument] if the task is not a Task object
    # @return [Deployment::Task]
    def dependency_forward_remove(task)
      raise Deployment::InvalidArgument.new self, 'Dependency should be a task!', task unless task.is_a? Task
      forward_dependencies.delete task
      task.backward_dependencies.delete self
      task
    end
    alias :remove_is_required :dependency_forward_remove
    alias :remove_depended_on :dependency_forward_remove
    alias :remove_before :dependency_forward_remove

    # Check if this task is within the backward dependencies
    # @param [Deployment::Task] task
    # @raise [Deployment::InvalidArgument] if the task is not a Task object
    # @return [Deployment::Task]
    def dependency_backward_present?(task)
      raise Deployment::InvalidArgument.new self, 'Dependency should be a task!', task unless task.is_a? Task
      backward_dependencies.member? task and task.forward_dependencies.member? self
    end
    alias :has_requires? :dependency_backward_present?
    alias :has_depends? :dependency_backward_present?
    alias :has_after? :dependency_backward_present?
    alias :dependency_present? :dependency_backward_present?
    alias :has_dependency? :dependency_backward_present?

    # Check if this task is within the forward dependencies
    # @param [Deployment::Task] task
    # @raise [Deployment::InvalidArgument] if the task is not a Task object
    # @return [Deployment::Task]
    def dependency_forward_present?(task)
      raise Deployment::InvalidArgument.new self, 'Dependency should be a task!', task unless task.is_a? Task
      forward_dependencies.member? task and task.backward_dependencies.member? self
    end
    alias :has_is_required? :dependency_forward_present?
    alias :has_depended_on? :dependency_forward_present?
    alias :has_before? :dependency_forward_present?

    # Check if there are any backward dependencies
    # @return [true, false]
    def dependency_backward_any?
      backward_dependencies.any?
    end
    alias :any_backward_dependency? :dependency_backward_any?
    alias :dependency_any? :dependency_backward_any?
    alias :any_dependency? :dependency_backward_any?

    # Check if there are any forward dependencies
    # @return [true, false]
    def dependency_forward_any?
      forward_dependencies.any?
    end
    alias :any_forward_dependencies? :dependency_forward_any?

    # Iterates through the backward dependencies
    # @yield [Deployment::Task]
    def each_backward_dependency(&block)
      backward_dependencies.each(&block)
    end
    alias :each :each_backward_dependency
    alias :each_dependency :each_backward_dependency

    # Iterates through the forward dependencies
    # @yield [Deployment::Task]
    def each_forward_dependency(&block)
      forward_dependencies.each(&block)
    end

    # Count the number of this task's forward dependencies
    # multiplied by 10 if they lead to the other nodes and
    # recursively adding their weights too.
    # This value can be used to determine how important this
    # task is and should be selected earlier.
    # @return [Integer]
    def weight
      return @weight if @weight
      @weight = each_forward_dependency.inject(0) do |weight, task|
        weight += task.node == self.node ? 1 : 10
        weight += task.weight
        weight
      end
    end

    # Check if any of direct backward dependencies of this
    # task are failed and set dep_failed status if so.
    # @return [true, false]
    def check_for_failed_dependencies
      return if self.sync_point?
      return false if FAILED_STATUSES.include? status
      failed = each_backward_dependency.any? do |task|
        FAILED_STATUSES.include? task.status
      end
      self.status = :dep_failed if failed
      failed
    end

    # Check if all direct backward dependencies of this task
    # are in success status and set task to ready if so and task is pending.
    # @return [true, false]
    def check_for_ready_dependencies
      return false unless status == :pending
      ready = each_backward_dependency.all? do |task|
        ready_statuses = SUCCESS_STATUSES
        ready_statuses += FAILED_STATUSES if sync_point?
        ready_statuses.include? task.status
      end
      self.status = :ready if ready
      ready
    end

    # set the pending tasks to dep_failed if the node have failed
    def check_for_node_status
      return unless node
      if NOT_RUN_STATUSES.include? status
        if Deployment::Node::FAILED_STATUSES.include? node.status
          self.status = :dep_failed
        end
        if node.status == :skipped
          self.status = :skipped
        end
      end
    end

    # Poll direct task dependencies if
    # the failed or ready status of this task should change
    def poll_dependencies
      check_for_ready_dependencies
      check_for_failed_dependencies
      check_for_node_status
    end
    alias :poll :poll_dependencies

    # Ask forward dependencies to check if their
    # status should be updated bue to change in this
    # task's status.
    def poll_forward
      each_forward_dependency do |task|
        task.check_for_ready_dependencies
        task.check_for_failed_dependencies
      end
    end

    # The task have finished, successful or not, and
    # will not run again in this deployment
    # @return [true, false]
    def finished?
      poll_dependencies
      FINISHED_STATUSES.include? status
    end

    # The task have successfully finished
    # @return [true, false]
    def successful?
      status == :successful
    end

    # The task was not run yet
    # @return [true, false]
    def pending?
      status == :pending
    end

    # The task have not run yet
    # @return [true, false]
    def new?
      NOT_RUN_STATUSES.include? status
    end

    # The task is running right now
    # @return [true, false]
    def running?
      status == :running
    end

    # The task is manually skipped
    # @return [true, false]
    def skipped?
      status == :skipped
    end

    # The task is ready to run,
    # it has all dependencies met and is in pending status
    # If the task has maximum concurrency set, it is checked too.
    # @return [true, false]
    def ready?
      poll_dependencies
      return false unless concurrency_available?
      status == :ready
    end

    # This task have been run but unsuccessfully
    # @return [true, false]
    def failed?
      poll_dependencies
      FAILED_STATUSES.include? status
    end

    # This task have not been run because of failed dependencies
    # @return [true, false]
    def dep_failed?
      status == :dep_failed
    end

    def is_skipped?
      @data.fetch('type', nil) == 'skipped'
    end

    # # This task failed
    # # @return [true, false]
    # def abortive?
    #   status == :failed
    # end

    #This task is sync point
    # @return [true, false]
    def sync_point?
      self.node.sync_point?
    end

    # @return [String]
    def to_s
      "Task[#{name}/#{node.name}]"
    end

    # @return [String]
    def inspect
      message = "#{self}{Status: #{status}"
      message += " After: #{dependency_backward_names.join ', '}" if dependency_backward_any?
      message += " Before: #{dependency_forward_names.join ', '}" if dependency_forward_any?
      message + '}'
    end

    # Get a sorted list of all this task's dependencies
    # @return [Array<String>]
    def dependency_backward_names
      each_backward_dependency.map do |task|
        task.to_s
      end.sort
    end
    alias :dependency_names :dependency_backward_names

    # Get a sorted list of all tasks that depend on this task
    # @return [Array<String>]
    def dependency_forward_names
      each_forward_dependency.map do |task|
        task.to_s
      end.sort
    end

    # Choose a color for a task vertex
    # according to the tasks status
    # @return [Symbol]
    def color
      poll_dependencies
      case status
        when :pending;
          sync_point? ? :cyan : :white
          is_skipped? ? :magenta : :white
        when :ready
          :yellow
        when :successful;
          :green
        when :failed;
          :red
        when :dep_failed;
          :orange
        when :skipped;
          :violet
        when :running;
          :blue
        else
          :white
      end
    end

    # Run this task on its node.
    # This task will pass itself to the abstract run method of the Node object
    # and set it's status to 'running'.
    def run
      info "Run on node: #{node}"
      self.status = :running
      node.run self
    end

  end
end


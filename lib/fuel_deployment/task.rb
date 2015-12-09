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
    def initialize(name, node, data=nil)
      self.name = name
      @status = :pending
      @backward_dependencies = Set.new
      @forward_dependencies = Set.new
      @data = data
      self.node = node
    end

    include Enumerable
    include Deployment::Log

    attr_reader :name
    attr_reader :node
    attr_reader :status
    attr_reader :backward_dependencies
    attr_reader :forward_dependencies
    attr_accessor :data

    # Walk the task graph forward using DFS algorithm
    # @param [Array<Deployment::Task>] visited The list of visited tasks for loop detection
    # @yield [Deployment::Task]
    def dfs_forward(visited = [], &block)
      return to_enum(:dfs_forward) unless block_given?
      if visited.include? self
        visited << self
        raise Deployment::LoopDetected.new self, 'Loop detected!', visited
      end
      visited << self
      yield self
      each_forward_dependency do |task|
        task.dfs_forward visited, &block
      end
      visited.delete self
    end

    # Walk the task graph backward using DFS algorithm
    # @param [Array<Deployment::Task>] visited The list of visited tasks for loop detection
    # @yield [Deployment::Task]
    def dfs_backward(visited = [], &block)
      return to_enum(:dfs_backward) unless block_given?
      if visited.include? self
        visited << self
        raise Deployment::LoopDetected.new self, 'Loop detected!', visited
      end
      visited << self
      yield self
      each_backward_dependency do |task|
        task.dfs_backward visited, &block
      end
      visited.delete self
    end

    # Set this task's Node object
    # @param [Deployment::Node] node The ne node object
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

    # Get the current concurrency value for a given task
    # or perform an action with this value.
    # @param [Deployment::Task, String, Symbol] task
    # @param [Symbol] action
    # @option action [Symbol] :inc Increase the value
    # @option action [Symbol] :dec Decrease the value
    # @option action [Symbol] :reset Set the value to zero
    # @option action [Symbol] :set Manually set the value
    # @param [Integer] value Manually set to this value
    # @return [Integer]
    def self.current_concurrency(task, action = :get, value = nil)
      @current_concurrency = {} unless @current_concurrency
      task = task.name if task.is_a? Deployment::Task
      key = task.to_sym
      @current_concurrency[key] = 0 unless @current_concurrency[key]
      return @current_concurrency[key] unless action
      if action == :inc
        @current_concurrency[key] += 1
      elsif action == :dec
        @current_concurrency[key] -= 1
      elsif action == :zero
        @current_concurrency[key] = 0
      elsif action == :set
        begin
          @current_concurrency[key] = Integer(value)
        rescue TypeError, ArgumentError
          raise Deployment::InvalidArgument.new self, 'Current concurrency should be an integer number!', value
        end
      end
      @current_concurrency[key] = 0 if @current_concurrency[key] < 0
      @current_concurrency[key]
    end

    # Get or set the maximum concurrency value for a given task.
    # Value is set if the second argument is provided.
    # @param [Deployment::Task, String, Symbol] task
    # @param [Integer, nil] value
    # @return [Integer]
    def self.maximum_concurrency(task, value = nil)
      @maximum_concurrency = {} unless @maximum_concurrency
      task = task.name if task.is_a? Deployment::Task
      key = task.to_sym
      @maximum_concurrency[key] = 0 unless @maximum_concurrency[key]
      return @maximum_concurrency[key] unless value
      begin
        @maximum_concurrency[key] = Integer(value)
      rescue TypeError, ArgumentError
        raise Deployment::InvalidArgument.new self, 'Maximum concurrency should be an integer number!', value
      end
      @maximum_concurrency[key]
    end

    # Get the maximum concurrency
    # @return [Integer]
    def maximum_concurrency
      self.class.maximum_concurrency self
    end

    # Set the maximum concurrency
    # @param [Integer] value
    # @return [Integer]
    def maximum_concurrency=(value)
      self.class.maximum_concurrency self, value
    end

    # Increase or decrease the concurrency value
    # when the task's status is changed.
    # @param [Symbol] status_from
    # @param [Symbol] status_to
    # @return [void]
    def status_changes_concurrency(status_from, status_to)
      return unless maximum_concurrency_is_set?
      if status_to == :running
        current_concurrency_increase
        info "Increasing concurrency to: #{current_concurrency}"
      elsif status_from == :running
        current_concurrency_decrease
        info "Decreasing concurrency to: #{current_concurrency}"
      end
    end

    # Get the current concurrency
    # @return [Integer]
    def current_concurrency
      self.class.current_concurrency self
    end

    # Increase the current concurrency by one
    # @return [Integer]
    def current_concurrency_increase
      self.class.current_concurrency self, :inc
    end

    # Decrease the current concurrency by one
    # @return [Integer]
    def current_concurrency_decrease
      self.class.current_concurrency self, :dec
    end

    # Reset the current concurrency to zero
    # @return [Integer]
    def current_concurrency_zero
      self.class.current_concurrency self, :zero
    end

    # Manually set the current concurrency value
    # @param [Integer] value
    # @return [Integer]
    def current_concurrency=(value)
      self.class.current_concurrency self, :set, value
    end

    # Check if there are concurrency slots available
    # to run this task.
    # @return [true, false]
    def concurrency_available?
      return true unless maximum_concurrency_is_set?
      current_concurrency < maximum_concurrency
    end

    # Check if the maximum concurrency of this task is set
    # @return [true, false]
    def maximum_concurrency_is_set?
      maximum_concurrency > 0
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

    # Check if any of direct backward dependencies of this
    # task are failed and set dep_failed status if so.
    # @return [true, false]
    def check_for_failed_dependencies
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
        SUCCESS_STATUSES.include? task.status
      end
      self.status = :ready if ready
      ready
    end

    # Poll direct task dependencies if
    # the failed or ready status of this task should change
    def poll_dependencies
      check_for_ready_dependencies
      check_for_failed_dependencies
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
      status == :ready
    end

    # This task have been run but unsuccessfully
    # @return [true, false]
    def failed?
      poll_dependencies
      FAILED_STATUSES.include? status
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
      names = []
      each_backward_dependency do |task|
        names << task.to_s
      end
      names.sort
    end
    alias :dependency_names :dependency_backward_names

    # Get a sorted list of all tasks that depend on this task
    # @return [Array<String>]
    def dependency_forward_names
      names = []
      each_forward_dependency do |task|
        names << task.to_s
      end
      names.sort
    end

    # Choose a color for a task vertex
    # according to the tasks status
    # @return [Symbol]
    def color
      poll_dependencies
      case status
        when :pending;
          :white
        when :ready
          :yellow
        when :successful;
          :green
        when :failed;
          :red
        when :dep_failed;
          :rose
        when :skipped;
          :purple
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

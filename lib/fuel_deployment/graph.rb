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

  # The graph object contains task objects
  # it can add and remove tasks and their dependencies
  # count tasks, check if tasks are finished and find
  # a next task that is ready to be run.
  # The graph should be assigned to a node object.
  #
  # @attr [Deployment::Node] node The node of this graph
  # @attr_reader [Hash<Symbol => Deployment::Task>] tasks The tasks of this graph
  class Graph

    # @param [Deployment::Node] node The new node that will be assigned to this graph
    # @return [void]
    def initialize(node)
      @tasks_have_failed = false
      @tasks_are_finished = false
      @tasks_are_successful = false
      self.node = node
      @tasks = {}
    end

    include Enumerable
    include Deployment::Log

    attr_reader :node
    attr_reader :tasks

    # Reset the dependency status mnemoization of this task
    # @return [void]
    def reset
      @tasks_have_failed = false
      @tasks_are_finished = false
      @tasks_are_successful = false
    end

    # Prepare the hash key from the task
    # @param [Deployment::Task,String,Symbol] task
    def prepare_key(task)
      task = task.name if task.is_a? Deployment::Task
      task.to_s.to_sym
    end

    # Retrieve a task object from the graph
    # @param [String, Symbol] task_name The name of the task to retrieve
    # @return [Deployment::Task]
    def task_get(task_name)
      tasks.fetch prepare_key(task_name), nil
    end
    alias :get_task :task_get
    alias :[] :task_get

    # Add an existing task object to the graph
    # @param [Deployment::Task] task a new task object
    # @raise [Deployment::InvalidArgument] If the object is not a task or the task is not from this graph
    # @return [Deployment::Task]
    def task_add(task)
      raise Deployment::InvalidArgument.new self, 'Graph can add only tasks!', task unless task.is_a? Deployment::Task
      return task_get task if task_present? task
      raise Deployment::InvalidArgument.new self, 'Graph cannot add tasks not for this node!', task unless task.node == node
      tasks.store prepare_key(task), task
      reset
      task
    end
    alias :add_task :task_add
    alias :add_vertex :task_add
    alias :vertex_add :task_add

    # Create a new task object by its name and add it to the graph.
    # Or, if the task already exists, return the existing object.
    # Assigns the data payload to the created or found task if this
    # parameter is provided.
    # @param [String, Symbol] task The name of the new task
    # @return [Deployment::Task]
    def task_create(task, data=nil)
      if task_present? task
        task = task_get task
      elsif task.is_a? Deployment::Task
        task = task_add task
      else
        task = Deployment::Task.new task, node, data
        task = task_add task
      end
      task.data = data if data
      task
    end
    alias :create_task :task_create
    alias :add_new_task :task_create
    alias :task_add_new :task_create
    alias :new_task :task_create
    alias :task_new :task_create

    # Create a new task object by name and add it into the graph.
    # Then add backward dependencies and forward dependencies for this object.
    # @param [String, Symbol, Deployment::Task] task_name The new task name
    # @param [Object] data The task data payload
    # @param [Array<String, Deployment::Task>] backward_deps The list of task names, this task depends on
    # @param [Array<String, Deployment::Task>] forward_deps The list of task names that depend on this task
    # @return [Deployment::Task]
    def task_add_new_with_dependencies(task_name, data=nil, backward_deps=[], forward_deps=[])
      task = task_create task_name, data
      backward_deps = [backward_deps] unless backward_deps.is_a? Array
      forward_deps = [forward_deps] unless forward_deps.is_a? Array
      backward_deps.each do |dependency|
        dependency = task_create dependency
        add_dependency dependency, task
      end
      forward_deps.each do |dependency|
        dependency = task_create dependency
        add_dependency task, dependency
      end
      task
    end
    alias :add_new_task_with_dependencies :task_add_new_with_dependencies

    # Check if the task is present in the graph
    # @param [Deployment::Task, String, Symbol] task_name
    # @return [true, false]
    def task_present?(task_name)
      tasks.key? prepare_key(task_name)
    end
    alias :has_task? :task_present?
    alias :key? :task_present?

    # Remove a task from this graph
    # @param [Deployment::Task, String, Symbol] task_name
    # @return [void]
    def task_remove(task_name)
      return unless task_present? task_name
      tasks.delete prepare_key(task_name)
      reset
    end
    alias :remove_task :task_remove

    # Add a dependency between tasks
    # @param [Deployment::Task, String, Symbol] task_from Graph edge from this task
    # @param [Deployment::Task, String, Symbol] task_to Graph edge to this task
    # @raise [Deployment::InvalidArgument] If you are referencing tasks by name
    # and there is no task with such name in this graph
    # @return [void]
    def add_dependency(task_from, task_to)
      unless task_from.is_a? Deployment::Task
        task_from = get_task task_from
        raise Deployment::NoSuchTask.new self, 'There is no such task in the graph!', task_from unless task_from
      end
      unless task_to.is_a? Deployment::Task
        task_to = get_task task_to
        raise Deployment::NoSuchTask.new self, 'There is no such task in the graph!', task_to unless task_to
      end
      task_to.dependency_backward_add task_from
    end
    alias :dependency_add :add_dependency
    alias :edge_add :add_dependency
    alias :add_edge :add_dependency

    # Set the node of this graph
    # @param [Deployment::Node] node A new node object
    # @raise [Deployment::InvalidArgument] If you pass a wrong object
    def node=(node)
      raise Deployment::InvalidArgument.new self, 'Not a node used instead of the graph node!', node unless node.is_a? Deployment::Node
      @node = node
    end

    # Return this graph's node name
    # @return [String]
    def name
      node.name
    end

    # Iterate through all the tasks in this graph
    # @yield [Deployment::Task]
    def each_task(&block)
      tasks.each_value(&block)
    end
    alias :each :each_task

    # Check if all the tasks in this graph are finished
    # memorises the positive result
    # @return [true, false]
    def tasks_are_finished?
      return true if @tasks_are_finished
      finished = all? do |task|
        task.finished?
      end
      if finished
        debug 'All tasks are finished'
        @tasks_are_finished = true
      end
      finished
    end
    alias :finished? :tasks_are_finished?

    # Check if all the tasks in this graph are successful
    # memorises the positive result
    # @return [true, false]
    def tasks_are_successful?
      return true if @tasks_are_successful
      return false if @tasks_have_failed
      successful = all? do |task|
        task.successful?
      end
      if successful
        debug 'All tasks are successful'
        @tasks_are_successful = true
      end
      successful
    end
    alias :successful? :tasks_are_successful?

    # Check if some of the tasks in this graph are failed
    # memorises the positive result
    # @return [true, false]
    def tasks_have_failed?
      return true if @tasks_have_failed
      failed = select do |task|
        task.failed?
      end
      if failed.any?
        debug "Found failed tasks: #{failed.map { |t| t.name }.join ', '}"
        @tasks_have_failed = true
      end
      failed.any?
    end
    alias :failed? :tasks_have_failed?

    # Find a task in the graph that has all dependencies met
    # and can be run right now
    # returns nil if there is no such task
    # @return [Deployment::Task, nil]
    def ready_task
      find do |task|
        task.ready?
      end
    end
    alias :next_task :ready_task

    # Get an array of task names
    # @return [Array<String>]
    def task_names
      map do |task|
        task.name
      end
    end

    # Count the total number of tasks
    # @return [Integer]
    def tasks_total_count
      tasks.length
    end

    # Count the number of the finished tasks
    # @return [Integer]
    def tasks_finished_count
      count do |task|
        task.finished?
      end
    end

    # Count the number of the failed tasks
    # @return [Integer]
    def tasks_failed_count
      count do |task|
        task.failed?
      end
    end

    # Count the number of the successful tasks
    # @return [Integer]
    def tasks_successful_count
      count do |task|
        task.successful?
      end
    end

    # Count the number of the pending tasks
    # @return [Integer]
    def tasks_pending_count
      count do |task|
        task.pending?
      end
    end

    # @return [String]
    def to_s
      "Graph[#{name}]"
    end

    # @return [String]
    def inspect
      message = "#{self}{"
      message += "Tasks: #{tasks_finished_count}/#{tasks_total_count}"
      message += " Finished: #{tasks_are_finished?} Failed: #{tasks_have_failed?} Successful: #{tasks_are_successful?}"
      message + '}'
    end
  end
end

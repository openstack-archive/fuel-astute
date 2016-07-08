#!/usr/bin/env ruby
#    Copyright 2016 Mirantis, Inc.
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

require_relative '../astute/exceptions'
require_relative '../astute/config'
require_relative '../fuel_deployment'
require_relative '../astute/task_deployment'
require 'active_support/all'
require 'yaml'
require 'optparse'
require 'find'

module Deployment
  class TestNode < Node
    def run(task)
      debug "Run task: #{task}"
      self.task = task
      self.status = :busy
    end

    def poll
      debug 'Poll node status'
      if busy?
        status = :successful
        status = :failed if cluster.tasks_to_fail.include? "#{task.name}/#{task.node.name}"
        info "#{task} finished with: #{status}"
        self.task.status = status
        self.status = :online
      end
    end

    attr_accessor :context
  end

  class TestCluster < Cluster
    def tasks_to_fail
      return @tasks_to_fail if @tasks_to_fail
      @tasks_to_fail = []
    end

    def tasks_to_fail=(value)
      @tasks_to_fail = value
    end

    attr_accessor :plot_post_node
    attr_accessor :plot_pre_node

    def hook_post_node(*args)
      return unless plot_post_node
      make_image
    end

    def hook_pre_node(*args)
      return unless plot_pre_node
      make_image
    end
  end
end

module Astute
  class SimulatorContext
    attr_accessor :reporter, :deploy_log_parser
    attr_reader :task_id, :status

    def initialize(task_id, reporter=nil, deploy_log_parser=nil)
      @task_id = task_id
      @reporter = reporter
      @status = {}
      @deploy_log_parser = deploy_log_parser
    end

    def report_and_update_status(_data)
    end

    def report(_msg)
    end
  end
end

module Astute
  class TaskDeployment
    def fail_offline_nodes(*_args)
      []
    end
  end
end

module Astute
  class Simulator
    # Parse the simulator CLI options
    # @return [Hash]
    def options
      return @options if @options
      @options = {}
      parser = OptionParser.new do |opts|
        opts.on('-l', '--list-yamls', 'List all deployment YAML files') do
          options[:list_yaml_files] = true
        end
        opts.on('-L', '--list-images', 'List all generated image files') do
          options[:list_image_files] = true
        end
        opts.on('-r', '--remove-yamls', 'Remove all deployment YAML files') do
          options[:remove_yaml_files] = true
        end
        opts.on('-R', '--remove-images', 'Remove all generated image files') do
          options[:remove_image_files] = true
        end
        opts.on('-y', '--yaml FILE', 'Load this file as the tasks graph from Astute') do |value|
          options[:yaml] = value
        end
        opts.on('-f', '--fail task/node,...', Array, 'Set the tasks that will fail during the simulation') do |value|
          options[:tasks_to_fail] = value
        end
        opts.on('-p', '--plot-first', 'Plot the first deployment step') do
          options[:plot_first] = true
        end
        opts.on('-P', '--plot-last', 'Plot the last deployment step') do
          options[:plot_last] = true
        end
        opts.on('-d', '--debug', 'Show debug messages') do
          options[:debug] = true
        end
        opts.on('-N', '--plot-pre-node', 'Make an image snapshot om every node visit before doing anything. It will create a lot of images!') do
          options[:plot_pre_node] = true
        end
        opts.on('-n', '--plot-post-node', 'Make an image snapshot after a task on a node have been run. Only impotent steps will be saved.') do
          options[:plot_post_node] = true
        end
        opts.on('-g', '--graph-task-filter REGEXP', 'Plot only tasks with matching name.') do |value|
          options[:graph_task_filter] = Regexp.new value
        end
        opts.on('-G', '--graph-node-filter REGEXP', 'Plot only tasks with matching node name.') do |value|
          options[:graph_node_filter] = Regexp.new value
        end
      end
      parser.banner = <<-eof
Usage: astute-simulator [options]

This tool uses the Astute task deployment libraries to simulate the deployment process.
It should load the YAML file with the tasks data dumps produced by Astute during the
deployment and run the simulated deployment. The output can be produced either as a
deployment log or as a set of graph image snapshots using Graphviz to render them.

You can use 'list-images' to locate the dumped YAML files and then
run the simulation like this:

# astute-simulator -y /path/to/yaml/file.yaml

The simulation should produce the log output displaying the which tasks and
on which nodes are being run as well as the deployment result status.
You can grep this log to determine the order the task will be started without
creating any graph images.

You can use 'plot-first' and 'plot-last' options to generate an SVG image of
the initial graph status and the result status of the deployment. It will
generate the 'start' and the 'end' images in the current directory.
You may have to download them from the Fuel master node in order to view them
on your system. The helper tools 'list-images' and 'remove-images' can be used
to manage the generated images.

Options 'plot-pre-node' and 'plot-post-node' will enable taking snapshots of the
graph status either before the node is processed or after the task have been
run on a node. These images can be very useful for debugging graph ordering
issues but it will take a lot of time to generate them if there are many tasks
in the graph.

Option 'fail' can be used to simulate a task failure.
The argument is a comma-separated list of task/node pairs like this:

# astute-simulator -y /path/to/yaml/file.yaml -f ntp-client/2,heat-db/1 -P

This command will simulate the fail of two task on the node1 and node2.
The final state of the graph will be plotted so the consequences of these failure
can be clearly seen.

The task status is color coded in the graph image:

* white  - A task has not been run yet.
* cyan   - A task is a sync-point (ignores dependency failures) and have not been run yet.
* yellow - A task has all dependencies satisfied or has none and can be started right now.
* blue   - A task is running right now.
* green  - A task has already been run and was successful.
* red    - A task has already been run and have failed.
* orange - A task has some failed dependencies or its node is failed and a task will not run.
* violet - A task is skipped or its node is skipped and a task will not run.

There are two filtering options 'graph-task-filter' and 'graph-node-filter'. You can use them
to limit the scope of plotted graph only to tasks with name or node name matching the provided
regular expressions. For example, plot only 'openstack' related tasks on the second node:

# astute-simulator -y /path/to/yaml/file.yaml -g openstack -G '^2$' -p

Limiting the number of plotted task will speed up the image generation and will make the
graph much more readable.

      eof
      parser.parse!
      @options[:yaml] = ARGV[0] unless @options[:yaml]
      @options
    end

    # Output the list of deployment YAML files
    def list_yaml_files
      yaml_files do |file|
        puts file
      end
    end

    # Output the list of generated image files
    def list_image_files
      image_files do |file|
        puts file
      end
    end

    # Remove all deployment YAML files
    def remove_yaml_files
      yaml_files do |file|
        puts "Remove: #{file}"
        File.unlink file if File.file? file
      end
    end

    # Remove all generated image files
    def remove_image_files
      image_files do |file|
        puts "Remove: #{file}"
        File.unlink file if File.file? file
      end
    end

    # Find all image files starting from the current folder
    def image_files
      return to_enum(:image_files) unless block_given?
      Find.find('.') do |file|
        next unless File.file? file
        next unless file.end_with?('.svg') or file.end_with?('.png')
        yield file
      end
    end

    # Find all deployment yaml files in the dot files dir
    def yaml_files
      return to_enum(:yaml_files) unless block_given?
      return unless File.directory? Astute.config.graph_dot_dir
      Find.find(Astute.config.graph_dot_dir) do |file|
        next unless File.file? file
        next unless file.end_with? '.yaml'
        yield file
      end
    end

    # Set the cluster options and run the simulation
    # @param cluster [Deployment::Cluster]
    def deploy(cluster)
      unless cluster.is_a? Deployment::Cluster
        raise Astute::DeploymentEngineError, "Argument should be a Cluster object! Got: #{cluster.class}"
      end

      if options[:debug]
        Deployment::Log.logger.level = Logger::DEBUG
      end

      if options[:tasks_to_fail]
        cluster.tasks_to_fail = options[:tasks_to_fail]
      end

      if options[:graph_task_filter]
        cluster.dot_task_filter = options[:graph_task_filter]
      end

      if options[:graph_node_filter]
        cluster.dot_node_filter = options[:graph_node_filter]
      end

      if options[:plot_first]
        cluster.make_image(suffix: 'start')
      end

      if options[:plot_pre_node]
        cluster.plot_pre_node = true
      end

      if options[:plot_post_node]
        cluster.plot_post_node = true
      end

      cluster.result_image_path = nil

      result = cluster.run

      if options[:plot_last]
        cluster.make_image(suffix: 'end')
      end

      cluster.info "Result: #{result.inspect}"
    end

    # Create a cluster object from the dumped YAML file
    # using the TaskDeployment class from Astute
    # @param yaml_file [String] Path to the YAML file
    # @return [Deployment::Cluster]
    def cluster_from_yaml(yaml_file=nil)
      raise Astute::DeploymentEngineError, 'No task YAML file have been provided!' unless yaml_file
      raise Astute::DeploymentEngineError, "No such file: #{yaml_file}" unless File.exists? yaml_file
      yaml_file_data = YAML.load_file yaml_file
      raise Astute::DeploymentEngineError, 'Wrong data! YAML should contain Hash!' unless yaml_file_data.is_a? Hash
      context = Astute::SimulatorContext.new 'simulator'
      deployment = Astute::TaskDeployment.new context, Deployment::TestCluster, Deployment::TestNode
      cluster = deployment.create_cluster yaml_file_data
      Deployment::Log.logger.level = Logger::INFO
      cluster.id = 'simulator'
      cluster
    end

    # Run an action based on options
    # @param cluster [Deployment::Cluster]
    def run(cluster=nil)
      if options[:list_yaml_files]
        list_yaml_files
      elsif options[:list_image_files]
        list_image_files
      elsif options[:remove_yaml_files]
        remove_yaml_files
      elsif options[:remove_image_files]
        remove_image_files
      else
        unless cluster
          if options[:yaml]
            cluster = cluster_from_yaml options[:yaml]
          else
            puts 'You have neither provided a task YAML file nor used a helper action!'
            puts 'Please, point the simulator at the task graph YAML dump using the "-y" option.'
            exit(1)
          end
        end
        deploy cluster
      end
    end

  end
end

#!/usr/bin/env ruby
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

require_relative '../astute/exceptions'
require_relative '../fuel_deployment'
require_relative '../astute/task_deployment'
require 'yaml'
require 'optparse'

module Deployment
  class TestNode < Node
    def run(task)
      fail Deployment::InvalidArgument, "#{self}: Node can run only tasks" unless task.is_a? Deployment::Task
      debug "Run task: #{task}"
      self.task = task
      self.status = :busy
    end

    def poll
      debug 'Poll node status'
      if busy?
        status = :successful
        status = :failed if cluster.tasks_to_fail.include? "#{task.name}/#{task.node.name}"
        debug "#{task} finished with: #{status}"
        self.task.status = status
        self.status = :online
      end
    end
  end

  class TestCluster < Cluster
    def tasks_to_fail
      return @tasks_to_fail if @tasks_to_fail
      @tasks_to_fail = []
    end

    def tasks_to_fail=(value)
      @tasks_to_fail = value
    end

    attr_accessor :plot
    def hook_pre_node(*args)
      make_image if plot
    end
  end
end

module Astute
  class Simulator < TaskDeployment
    def initialize
    end

    def cluster(tasks_graph: {})
      raise Astute::DeploymentEngineError, 'Deployment graph was not provided!' if tasks_graph.empty?

      cluster = Deployment::TestCluster.new

      tasks_graph.keys.each do |node_id|
        node = Deployment::TestNode.new(node_id, cluster)
        # node.set_critical if critical_node_uids(deployment_info).include?(node_id)
        # node.set_status_failed if offline_uids.include? node_id
      end

      setup_tasks(tasks_graph, cluster)
      setup_task_depends(tasks_graph, cluster)
      setup_task_concurrency(tasks_graph, cluster)

      cluster
    end

    def options
      return @options if @options
      @options = {}
      OptionParser.new do |opts|
        opts.on('-y', '--yaml FILE', 'Load this file as the tasks graph from Astute') do |value|
          if value
            fail "No such file: #{value}" unless File.exists? value
          end
          options[:yaml] = value
        end
        opts.on('-f', '--fail task/node,...', Array, 'Set the tasks that will fail during the simulation') do |value|
          options[:tasks_to_fail] = value
        end
        opts.on('-p', '--plot', 'Plot every step of the deployment simulation') do |value|
          options[:plot] = value
        end
        opts.on('-i', '--interactive', 'Run the interactive console') do |value|
          options[:interactive] = value
        end
        opts.on('-d', '--debug', 'Show debug messages') do
          Deployment::Log.logger.level = Logger::DEBUG
        end
      end.parse!
      @options
    end

    def from_tasks_yaml(tasks_yaml_file=nil)
      tasks_yaml_file = options[:yaml] unless tasks_yaml_file
      tasks_graph = YAML.load_file tasks_yaml_file
      raise Astute::DeploymentEngineError, 'Wrong data! YAML should contain Hash!' unless tasks_graph.is_a? Hash

      Deployment::Log.logger.level = Logger::INFO

      cluster = self.cluster(tasks_graph: tasks_graph)
      cluster.id = 'simulator'

      if options[:fail]
        cluster.tasks_to_fail = options[:tasks_to_fail]
      end

      if options[:plot]
        cluster.plot = true
      end

      if options[:interactive]
        binding.pry
      else
        result = cluster.run
        puts "Result: #{result.inspect}"
      end
    end

  end
end

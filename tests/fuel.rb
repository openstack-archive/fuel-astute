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

require File.absolute_path File.join File.dirname(__FILE__), 'test_node.rb'
require 'yaml'

file = if File.file? ARGV[0].to_s
         ARGV[0].to_s
       else
         File.join File.dirname(__FILE__), 'fuel.yaml'
       end

deployment_tasks = YAML.load_file file
fail 'Wrong data! YAML should contain Hash!' unless deployment_tasks.is_a? Hash

cluster = Deployment::TestCluster.new
cluster.id = 'fuel'
cluster.plot = true if options[:plot]

deployment_tasks.each do |node_name, node_tasks|
  node = cluster.node_create node_name, Deployment::TestNode
  node_tasks.each do |task_data|
    cluster[node].create_task task_data['id'], task_data
  end
end

deployment_tasks.each do |node_name, node_tasks|
  node_tasks.each do |task_data|
    task_name = task_data['id']
    task = cluster[node_name][task_name]

    requires = task_data.fetch 'requires', []
    requires.each do |requirement|
      next unless requirement.is_a? Hash
      required_task = cluster[requirement['node_id']][requirement['name']]
      unless required_task
        warn "Task: #{requirement['name']} is not found on node: #{cluster[requirement['node_id']]}"
        next
      end
      task.requires required_task
    end

    required_for = task_data.fetch 'required_for', []
    required_for.each do |requirement|
      next unless requirement.is_a? Hash
      required_by_task = cluster[requirement['node_id']][requirement['name']]
      task = cluster[node_name][task_data['id']]
      unless required_by_task
        warn "Task: #{requirement['name']} is not found on node: #{cluster[requirement['node_id']]}"
        next
      end
      task.is_required required_by_task
    end
  end
end

if options[:plot]
  cluster.make_image 'start'
end

if options[:interactive]
  binding.pry
else
  cluster.run
end

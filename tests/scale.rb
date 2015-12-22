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

TASK_NUMBER = 100
NODE_NUMBER = 100

cluster = Deployment::TestCluster.new
cluster.id = 'scale'
cluster.plot = true if options[:plot]

def make_nodes(cluster)
  1.upto(NODE_NUMBER).map do |node|
    Deployment::TestNode.new "node#{node}", cluster
  end
end

def make_tasks(node)
  previous_task = nil
  1.upto(TASK_NUMBER).each do |number|
    task = "task#{number}"
    unless previous_task
      previous_task = task
      next
    end
    task_from = node.graph.create_task previous_task
    task_to = node.graph.create_task task
    node.graph.add_dependency task_from, task_to
    previous_task = task
  end
end

make_nodes cluster

cluster.each_node do |node|
  puts "Make tasks for: #{node}"
  make_tasks node
  nil
end

cluster.each_node do |node|
  next if node.name == 'node1'
  node['task10'].depends cluster['node1']['task50']
end

if options[:plot]
  cluster.make_image 'start'
end

if options[:interactive]
  binding.pry
else
  cluster.run
end

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

cluster = Deployment::TestCluster.new 'mini'
cluster.plot = true if options[:plot]
node1 = Deployment::TestNode.new 'node1', cluster

node1.graph.add_new_task 'task1'
node1.graph.add_new_task 'task2'
node1.graph.add_new_task 'task3'

node1['task1'].before node1['task2']
node1['task2'].before node1['task3']

if options[:plot]
  cluster.make_image 'start'
end

if options[:interactive]
  binding.pry
else
  cluster.run
end

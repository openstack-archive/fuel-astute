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

require_relative '../lib/fuel_deployment/simulator'

simulator = Astute::Simulator.new
simulator.tools
cluster = Deployment::TestCluster.new
cluster.id = 'deployment'

node1_data = [
    [0, 1],
    [1, 2],
    [1, 3],
    [2, 4],
    [2, 5],
    [3, 6],
    [3, 7],
    [4, 8],
    [5, 10],
    [6, 11],
    [7, 12],
    [8, 9],
    [10, 9],
    [11, 13],
    [12, 13],
    [13, 9],
    # [9, 14],
    [14, 15],
]

node2_data = [
    [0, 1],
    [1, 2],
    [0, 3],
    [3, 4],
    [4, 5],
    # [5, 6],
    [5, 7],
    [6, 8],
]

cluster = Deployment::TestCluster.new
cluster.id = 'deployment'

node1 = cluster.node_create 'node1', Deployment::TestNode
node2 = cluster.node_create 'node2', Deployment::TestNode
sync_node = cluster.node_create 'sync_node', Deployment::TestNode
node2.set_critical
sync_node.set_as_sync_point
sync_node.create_task 'sync_task'

node1_data.each do |task_from, task_to|
  task_from = node1.graph.create_task "task#{task_from}"
  task_to = node1.graph.create_task "task#{task_to}"
  node1.graph.add_dependency task_from, task_to
end

node2_data.each do |task_from, task_to|
  task_from = node2.graph.create_task "task#{task_from}"
  task_to = node2.graph.create_task "task#{task_to}"
  node2.graph.add_dependency task_from, task_to
end

node2['task4'].depends node1['task3']
node2['task5'].depends node1['task13']
node1['task15'].depends node2['task6']

sync_node['sync_task'].depends node2['task5']
sync_node['sync_task'].depends node1['task9']
node2['task6'].depends sync_node['sync_task']
node1['task14'].depends sync_node['sync_task']

simulator.run cluster

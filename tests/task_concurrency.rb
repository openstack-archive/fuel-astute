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
cluster.id = 'task_concurrency'

node1 = Deployment::TestNode.new 'node1', cluster
node2 = Deployment::TestNode.new 'node2', cluster
node3 = Deployment::TestNode.new 'node3', cluster
node4 = Deployment::TestNode.new 'node4', cluster
node5 = Deployment::TestNode.new 'node5', cluster

node1.add_new_task('task1')
node1.add_new_task('final')

node2.add_new_task('task1')
node2.add_new_task('final')

node3.add_new_task('task1')
node3.add_new_task('final')

node4.add_new_task('task1')
node4.add_new_task('final')

node5.add_new_task('task1')
node5.add_new_task('final')

node1['final'].after node1['task1']
node2['final'].after node2['task1']
node3['final'].after node3['task1']
node4['final'].after node4['task1']
node5['final'].after node5['task1']

cluster.task_concurrency['task1'].maximum = 3
cluster.task_concurrency['final'].maximum = 2

simulator.run cluster

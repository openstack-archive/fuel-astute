#    Copyright 2014 Mirantis, Inc.
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


require File.join(File.dirname(__FILE__), '../spec_helper')

include Astute

describe "PuppetdDeployer" do
  include SpecHelpers

  let(:nodes) do
    [
      {
        'uid' => '1',
        'role' => 'primary-controller',
        'tasks' => [
          {'name' => 'pr_controller_1', 'description' => 'test1'},
          {'name' => 'pr_controller_2', 'description' => 'test2'},
          {'name' => 'controller_3', 'description' => 'test3'}
        ],
        'fail_if_error' => true
      },
      {
        'uid' => '2',
        'role' => 'controller',
        'tasks' => [
          {'name' => 'controller_1', 'description' => 'test1'},
          {'name' => 'controller_3', 'description' => 'test3'}
        ],
        'fail_if_error' => false
      }
    ]
  end

  let(:ctx) do
    ctx = mock
    ctx.stubs(:task_id)
    ctx.stubs(:deploy_log_parser).returns(Astute::LogParser::NoParsing.new)
    ctx.stubs(:status).returns({})
    reporter = mock
    reporter.stubs(:report)
    up_reporter = Astute::ProxyReporter::DeploymentProxyReporter.new(reporter, nodes)
    ctx.stubs(:reporter).returns(up_reporter)
    ctx
  end

  describe '.deploy' do
    it 'should deploy nodes' do
      PuppetdDeployer.expects(:deploy_nodes).once

      PuppetdDeployer.deploy(ctx, nodes)
    end

    it 'should use puppet task for deploy' do
      puppet_task = mock('puppet_task')
      PuppetdDeployer.expects(:puppet_task).with(nodes[0]).returns(puppet_task)
      PuppetdDeployer.expects(:puppet_task).with(nodes[1]).returns(puppet_task)
      puppet_task.expects(:run).times(nodes.size)
      puppet_task.stubs(:status).returns('ready')

      PuppetdDeployer.deploy(ctx, nodes)
    end

    it 'should sleep between status checks' do
      puppet_task = mock('puppet_task')
      PuppetdDeployer.expects(:puppet_task).with(nodes[0]).returns(puppet_task)
      PuppetdDeployer.expects(:puppet_task).with(nodes[1]).returns(puppet_task)
      puppet_task.stubs(:run).times(nodes.size)
      puppet_task.stubs(:status).returns('deploying')
        .then.returns('ready')
        .then.returns('ready')

      PuppetdDeployer.expects(:sleep).with(Astute.config.PUPPET_DEPLOY_INTERVAL)
      PuppetdDeployer.deploy(ctx, nodes)
    end
  end

end
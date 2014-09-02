#    Copyright 2013 Mirantis, Inc.
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

describe "TaskLib DeploymentEngine" do
  include SpecHelpers

  let(:deploy_engine) do
    Astute::DeploymentEngine::Tasklib.new(ctx)
  end

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

  let(:mclient) do
    mclient = mock_rpcclient([nodes.first])
    Astute::MClient.any_instance.stubs(:rpcclient).returns(mclient)
    Astute::MClient.any_instance.stubs(:log_result).returns(mclient)
    Astute::MClient.any_instance.stubs(:check_results_with_retries).returns(mclient)
    mclient
  end

  context 'call structure' do
    it 'run pre tasks hook' do
      deploy_engine.stubs(:deploy_nodes)
      deploy_engine.stubs(:post_tasklib_deploy)
      deploy_engine.expects(:pre_tasklib_deploy).once

      deploy_engine.deploy_piece(nodes)
    end

    it 'run tasks deploy' do
      deploy_engine.stubs(:pre_tasklib_deploy)
      deploy_engine.stubs(:post_tasklib_deploy).once

      deploy_engine.expects(:deploy_nodes)

      deploy_engine.deploy_piece(nodes)
    end

    it 'run after tasks hook' do
      deploy_engine.stubs(:pre_tasklib_deploy)
      deploy_engine.stubs(:deploy_nodes)

      deploy_engine.expects(:post_tasklib_deploy).once

      deploy_engine.deploy_piece(nodes)
    end
  end #'call structure'

  context 'pre tasks hook' do
    before(:each) do
      deploy_engine.stubs(:deploy_nodes)
      deploy_engine.stubs(:post_tasklib_deploy)
    end

    it 'send initial status for node' do
      deploy_engine.stubs(:upload_facts)

      ctx.reporter.expects(:report).with('nodes' => [
        {'uid' => '1', 'status' => 'deploying', 'role' => 'primary-controller', 'progress' => 0},
        {'uid' => '2', 'status' => 'deploying', 'role' => 'controller', 'progress' => 0}
      ]).once

      deploy_engine.deploy_piece(nodes)
    end
  end

  context 'post tasks hook' do
    before(:each) do
      deploy_engine.stubs(:pre_tasklib_deploy)
      deploy_engine.stubs(:deploy_nodes)
    end

    it 'show spend time' do
      deploy_engine.instance_variable_set(:@time_before, Time.now.to_i)
      deploy_engine.deploy_piece(nodes)
    end
  end

  context 'task flow' do
    before(:each) do
      deploy_engine.stubs(:pre_tasklib_deploy)
      deploy_engine.stubs(:post_tasklib_deploy)

      deploy_engine.stubs(:check_status)
        .with('1', 'pr_controller_1')
        .returns(:running)
        .then.returns(:ended_successfully)
      deploy_engine.stubs(:check_status).with('1', 'pr_controller_2')
        .returns(:running)
        .then.returns(:running)
        .then.returns(:ended_successfully)
      deploy_engine.stubs(:check_status).with('1', 'controller_3')
        .returns(:ended_successfully)
      deploy_engine.stubs(:check_status).with('2', 'controller_1')
        .returns(:running)
        .then.returns(:unexpected_error)
    end

    it 'run all tasks' do
      deploy_engine.expects(:run_task).with('1', 'pr_controller_1')
      deploy_engine.expects(:run_task).with('1', 'pr_controller_2')
      deploy_engine.expects(:run_task).with('1', 'controller_3')
      deploy_engine.expects(:run_task).with('2', 'controller_1')

      ctx.stubs(:report_and_update_status)
      deploy_engine.deploy_piece(nodes)
    end

    it 'report and update node status' do
      deploy_engine.stubs(:run_task).times(4)

      mock_calculator = mock
      ctx.stubs(:deploy_log_parser).returns(mock_calculator)

      mock_calculator.stubs(:progress_calculate).with(['1'], anything).returns(
        ['uid' => '1',
        'progress' => 30]
      )

      mock_calculator.stubs(:progress_calculate).with(['2'], anything).returns(
        ['uid' => '2',
        'progress' => 50]
      )

      ctx.expects(:report_and_update_status).with('nodes' => [
        {'uid' => '1', 'status' => 'deploying', 'role' => 'primary-controller', 'progress' => 30, 'task' => 'pr_controller_1'},
        {'uid' => '2', 'status' => 'deploying', 'role' => 'controller', 'progress' => 50, 'task' => 'controller_1'}])

      ctx.expects(:report_and_update_status).with('nodes' => [
        {'uid' => '1', 'status' => 'deploying', 'role' => 'primary-controller', 'progress' => 30, 'task' => 'pr_controller_2'}
      ]).twice

      ctx.expects(:report_and_update_status).with('nodes' => [
        {'uid' => '1', 'status' => 'ready', 'role' => 'primary-controller', 'progress' => 100, 'task' => 'controller_3'}
      ])

      ctx.expects(:report_and_update_status).with('nodes' => [
        {'uid' => '2', 'status' => 'error', 'error_type' => 'deploy', 'role' => 'controller', 'task' => 'controller_1'}
      ])

      deploy_engine.deploy_piece(nodes)
    end

    it 'raise error if tasklib return known status without handler' do
      deploy_engine.stubs(:run_task)
      deploy_engine.stubs(:check_status)
        .with('1', 'pr_controller_1')
        .returns(:unknown_state)

      expect { deploy_engine.deploy_piece(nodes) }.to raise_error(/Known status 'unknown_state', but handler not provided/)
    end

    it 'raise error if tasklib return unknown exit code' do
      deploy_engine.stubs(:run_task)
      ctx.stubs(:report_and_update_status)
      deploy_engine.unstub(:check_status)

      mclient.stubs(:execute).returns([{:data => {:exit_code => '12'}}])

      expect { deploy_engine.deploy_piece(nodes) }.to raise_error(/Internal error. Unknown status '12'/)
    end

    it 'run task using tasklib' do
      ctx.stubs(:report_and_update_status)

      tasklib_mclient = mock('tasklib_mclient')
      deploy_engine.stubs(:tasklib_mclient).with(is_a(String)).returns(tasklib_mclient)

      tasklib_mclient.expects(:execute).with(has_entry(:cmd => regexp_matches(/taskcmd  daemon/))).returns([]).times(4)

      deploy_engine.deploy_piece(nodes)
    end

    it 'run with debug option if debug option is true' do
      ctx.stubs(:report_and_update_status)
      nodes.first['debug'] = true

      tasklib_mclient = mock('tasklib_mclient')
      deploy_engine.stubs(:tasklib_mclient).with(is_a(String)).returns(tasklib_mclient)

      tasklib_mclient.expects(:execute).with(has_entry(:cmd => regexp_matches(/taskcmd --debug daemon/))).returns([]).times(4)

      deploy_engine.deploy_piece(nodes)
    end

  end
end

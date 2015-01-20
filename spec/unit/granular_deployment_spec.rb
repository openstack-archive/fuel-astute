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

describe "Granular deployment engine" do
  include SpecHelpers

  let(:ctx) {
    ctx = mock
    ctx.stubs(:task_id)
    ctx.stubs(:deploy_log_parser).returns(Astute::LogParser::NoParsing.new)
    ctx.stubs(:status).returns({})
    reporter = mock
    reporter.stubs(:report)
    up_reporter = Astute::ProxyReporter::DeploymentProxyReporter.new(reporter, nodes)
    ctx.stubs(:reporter).returns(up_reporter)
    ctx
  }

  let(:deploy_engine) do
    Astute::DeploymentEngine::GranularDeployment.new(ctx)
  end

  let(:upload_file_hook) do
    {
      "priority" =>  100,
      "type" =>  "upload_file",
      "fail_on_error" => false,
      "diagnostic_name" => "upload-example-1.0",
      "uids" =>  ['2', '3'],
      "parameters" =>  {
        "path" =>  "/etc/yum.repos.d/fuel_awesome_plugin-0.1.0.repo",
        "data" =>  "[fuel_awesome_plugin-0.1.0]\\nname=Plugin fuel_awesome_plugin-0.1.0 repository\\nbaseurl=http => //10.20.0.2 => 8080/plugins/fuel_awesome_plugin-0.1.0/repositories/centos\\ngpgcheck=0"
      }
    }
  end

  let(:sync_hook) do
    {
      "priority" =>  200,
      "type" =>  "sync",
      "fail_on_error" => false,
      "diagnostic_name" => "sync-example-1.0",
      "uids" =>  ['1', '2'],
      "parameters" =>  {
        "src" =>  "rsync://10.20.0.2/plugins/fuel_awesome_plugin-0.1.0/deployment_scripts/",
        "dst" =>  "/etc/fuel/plugins/fuel_awesome_plugin-0.1.0/"
      }
    }
  end

  let(:shell_hook) do
    {
      "priority" =>  100,
      "type" =>  "shell",
      "fail_on_error" => false,
      "diagnostic_name" => "shell-example-1.0",
      "uids" =>  ['1','2','3'],
      "parameters" =>  {
        "cmd" =>  "./deploy.sh",
        "cwd" =>  "/etc/fuel/plugins/fuel_awesome_plugin-0.1.0/",
        "timeout" =>  60
      }
    }
  end

  let(:puppet_hook) do
    {
      "priority" =>  300,
      "type" =>  "puppet",
      "fail_on_error" => false,
      "diagnostic_name" => "puppet-example-1.0",
      "uids" =>  ['1', '3'],
      "parameters" =>  {
        "puppet_manifest" =>  "cinder_glusterfs.pp",
        "puppet_modules" =>  "modules",
        "cwd" => "/etc/fuel/plugins/plugin_name-1.0",
        "timeout" =>  42
      }
    }
  end

  let(:nodes) do
    [
      {
        'uid' => '45',
        'priority' => 200,
        'role' => 'ceph',
        'tasks' => [
          {
           'priority' => 100,
           'type' => 'puppet',
           'uids' => ['45']
          },
          {
           'priority' => 300,
           'type' => 'puppet',
           'uids' => ['45']
          }
        ]
      },
      {
        'uid' => '46',
        'priority' => 200,
        'role' => 'compute',
        'tasks' => [
          {
           'priority' => 100,
           'type' => 'puppet',
           'uids' => ['46']
          },
          {
           'priority' => 200,
           'type' => 'puppet',
           'uids' => ['46']
          },
          {
           'priority' => 300,
           'type' => 'puppet',
           'uids' => ['46']
          }
        ]
      }
    ]
  end

  describe '#deploy_piace' do
    it 'should run tasks using puppet task' do
      ctx.stubs(:report_and_update_status)
      deploy_engine.expects(:deploy_nodes).with(nodes)

      deploy_engine.deploy_piece(nodes)
    end

    it 'should not run if no tasks exists' do
      nodes[0]['tasks'] = []
      nodes[1]['tasks'] = []

      deploy_engine.expects(:deploy_nodes).never

      ready_report = {'nodes' => [
          {'uid' => '45',
            'status' => 'ready',
            'role' => 'ceph',
            'progress' => 100},
          {'uid' => '46',
            'status' => 'ready',
            'role' => 'compute',
            'progress' => 100}]}

      ctx.reporter.expects(:report).once.with(ready_report)

      deploy_engine.deploy_piece(nodes)
    end

    it 'should process only nodes with tasks' do
      ctx.stubs(:report_and_update_status)
      nodes[0]['tasks'] = []

      deploy_engine.expects(:deploy_nodes).with([nodes[1]])

      deploy_engine.deploy_piece(nodes)
    end

    it 'should report error status if error raised' do
      error_report = {'nodes' =>
        [
          {
            'uid' => '45',
            'status' => 'error',
            'role' => 'ceph',
            'error_type' => 'deploy'
          },
          {
            'uid' => '46',
            'status' => 'error',
            'role' => 'compute',
            'error_type' => 'deploy'
          }
        ]
      }

      ctx.expects(:report_and_update_status).with(error_report)
      deploy_engine.expects(:deploy_nodes).with(nodes).raises("Error simulation")

      deploy_engine.deploy_piece(nodes) rescue nil
    end

    it 'should not raise errir if no nodes was sent' do
      expect{ deploy_engine.deploy_piece([])}.to_not raise_error
    end

    it 'should prepare log for parsing' do
      deploy_engine.stubs(:deploy_nodes).with(nodes)

      ctx.deploy_log_parser.expects(:prepare).with(nodes).once
      deploy_engine.deploy_piece(nodes)
    end
  end # 'deploy_piace'

  describe '#deploy_nodes' do
    it 'run deploy task on nodes' do
      ctx.stubs(:report_and_update_status)
      deploy_engine.expects(:run_task).times(5)

      deploy_engine.stubs(:check_status).with('46')
        .returns('deploying').then
        .returns('ready').then
        .returns('deploying').then
        .returns('ready').then
        .returns('deploying').then
        .returns('ready')

      deploy_engine.stubs(:check_status).with('45')
        .returns('deploying').then
        .returns('ready').then
        .returns('deploying').then
        .returns('ready')

      deploy_engine.deploy_piece(nodes)
    end

    it 'report status about nodes' do
      deploy_engine.stubs(:run_task).times(5)

      deploy_engine.stubs(:check_status).with('46')
        .returns('deploying').then
        .returns('ready').then
        .returns('deploying').then
        .returns('ready').then
        .returns('deploying').then
        .returns('ready')

      deploy_engine.stubs(:check_status).with('45')
        .returns('deploying').then
        .returns('ready').then
        .returns('deploying').then
        .returns('ready')

      succeed_report_node1 = {
        'nodes' => [
          {
            'uid' => '45',
            'status' => 'ready',
            'role' => 'ceph',
            'progress' => 100,
            'task' => {'priority' => 300, 'type' => 'puppet', 'uids' => ['45']}
          }
        ]
      }
      succeed_report_node2 = {
        'nodes' => [
          {
            'uid' => '46',
            'status' => 'ready',
            'role' => 'compute',
            'progress' => 100,
            'task' => {'priority' => 300, 'type' => 'puppet', 'uids' => ['46']}
          }
        ]
      }

      ctx.expects(:report_and_update_status).with(succeed_report_node1).times(1)
      ctx.expects(:report_and_update_status).with(succeed_report_node2).times(1)

      deploy_engine.deploy_piece(nodes)
    end

    it 'handle error nodes and do not process next tasks on problem node' do
      deploy_engine.expects(:run_task).times(4)

      deploy_engine.stubs(:check_status).with('46')
        .returns('deploying').then
        .returns('ready').then
        .returns('deploying').then
        .returns('error')

      deploy_engine.stubs(:check_status).with('45')
        .returns('deploying').then
        .returns('ready').then
        .returns('deploying').then
        .returns('ready')

      mixed_report = {'nodes' =>
        [
          {
            'uid' => '45',
            'status' => 'ready',
            'role' => 'ceph',
            'progress' => 100,
            'task' => {'priority' => 300, 'type' => 'puppet', 'uids' => ['45']}
          },
          {
            'uid' => '46',
            'status' => 'error',
            'error_type' => 'deploy',
            'role' => 'compute',
            'task' => {'priority' => 200, 'type' => 'puppet', 'uids' => ['46']}
            }
          ]
        }
      ctx.expects(:report_and_update_status).with(mixed_report)

      deploy_engine.deploy_piece(nodes)
    end

    it 'handle sutuation then all nodes failed' do
      deploy_engine.expects(:run_task).times(2)

      deploy_engine.stubs(:check_status).with('46')
        .returns('deploying').then
        .returns('error')

      deploy_engine.stubs(:check_status).with('45')
        .returns('deploying').then
        .returns('error')

      error_report = {'nodes' =>
        [
          {
            'uid' => '45',
            'status' => 'error',
            'error_type' => 'deploy',
            'role' => 'ceph',
            'task' => {'priority' => 100, 'type' => 'puppet', 'uids' => ['45']}
          },
          {
            'uid' => '46',
            'status' => 'error',
            'error_type' => 'deploy',
            'role' => 'compute',
            'task' => {'priority' => 100, 'type' => 'puppet', 'uids' => ['46']}
          }
        ]
      }
      ctx.expects(:report_and_update_status).with(error_report)
      deploy_engine.deploy_piece(nodes)
    end

    it 'should fail deployment if handler not provided' do
      deploy_engine.expects(:run_task).times(2)
      deploy_engine.stubs(:check_status).returns('unknown_handler')

      error_report = {'nodes' =>
        [
          {
            'uid' => '45',
            'status' => 'error',
            'error_type' => 'deploy',
            'role' => 'ceph'
          },
          {
            'uid' => '46',
            'status' => 'error',
            'error_type' => 'deploy',
            'role' => 'compute'
          }
        ]
      }

      ctx.expects(:report_and_update_status).with(error_report)
      expect {deploy_engine.deploy_piece(nodes) }
        .to raise_error(/Internal error. Known status/)
    end

  end #deploy_nodes

end # 'describe'

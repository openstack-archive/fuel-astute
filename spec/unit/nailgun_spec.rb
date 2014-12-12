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

include Astute

describe "Nailgun DeploymentEngine" do
  include SpecHelpers

  let(:ctx) { mock_ctx }

  let(:deploy_engine) do
    Astute::DeploymentEngine::Nailgun.new(ctx)
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
    it 'should run nailgun tasks' do
      ctx.stubs(:report_and_update_status)
      NailgunHooks.any_instance.expects(:process)
      deploy_engine.deploy_piece(nodes)
    end

    it 'should group task by priority' do
      hook = mock('hook')
      NailgunHooks.expects(:new).with(
        [
          {
            "priority"=>100,
            "type"=>"puppet",
            "uids"=>["45", "46"]
          },
          {
            "priority"=>300,
            "type"=>"puppet",
            "uids"=>["45", "46"]
          },
          {
            "priority"=>200,
            "type"=>"puppet",
            "uids"=>["46"]
          }
        ],
        ctx).returns(hook)
      hook.stubs(:process)
      ctx.stubs(:report_and_update_status)

      deploy_engine.deploy_piece(nodes)
    end

    it 'should report success status about nodes' do
      NailgunHooks.any_instance.expects(:process)
      ctx.expects(:report_and_update_status).with(
        'nodes' =>
          [
            {'uid' => '45', 'status' => 'ready', 'role' => 'ceph'},
            {'uid' => '46', 'status' => 'ready', 'role' => 'compute'}
          ])

      deploy_engine.deploy_piece(nodes)
    end
  end

end # 'describe'

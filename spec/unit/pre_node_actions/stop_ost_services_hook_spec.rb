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

require File.join(File.dirname(__FILE__), '../../spec_helper')

describe Astute::StopOSTServices do
  include SpecHelpers

  let(:ctx) do
    ctx = mock('context')
    ctx.stubs(:task_id)
    ctx.stubs(:reporter)
    ctx.stubs(:status).returns('1' => 'success', '2' => 'success')
    ctx
  end

  let(:deploy_data) { [
      {'uid' => '1',
       'role' => 'controller',
       'openstack_version_prev' => 'old_version',
       'nodes' => [
           {
               'uid' => 1,
               'slave_name' => 'node-1',
               'role' => 'controller'
           },
           {
               'uid' => 2,
               'slave_name' => 'node-2',
               'role' => 'ceph-osd'
           }
       ],
      },
      {
          'uid' => '2',
          'role' => 'compute'
      }
  ]
  }

  let(:stop_ost_services) { Astute::StopOSTServices.new }

  it 'should run if upgrade/downgrade env' do
    stop_ost_services.expects(:upload_script).once
    stop_ost_services.expects(:run_shell_command).once.returns(:data => {:exit_code => 0})
    stop_ost_services.process(deploy_data, ctx)
  end

  it 'should not run if deploy new env' do
    deploy_data.first.delete('openstack_version_prev')
    stop_ost_services.process(deploy_data, ctx)
    stop_ost_services.expects(:upload_script).never
    stop_ost_services.expects(:run_shell_command).never

    stop_ost_services.process(deploy_data, ctx)
  end

  it 'should not change deployment status if command fail' do
    stop_ost_services.stubs(:upload_script).once
    stop_ost_services.expects(:run_shell_command).once.returns(:data => {:exit_code => 1})
    ctx.expects(:report_and_update_status).never

    stop_ost_services.process(deploy_data, ctx)
  end

  it 'should not change deployment status if shell exec using mcollective fail' do
    stop_ost_services.stubs(:upload_script).once
    stop_ost_services.expects(:run_shell_command).once.returns(:data => {})

    stop_ost_services.process(deploy_data, ctx)
    ctx.expects(:report_and_update_status).never
  end

  it 'should raise exception if shell exec using mcollective fail' do
    stop_ost_services.expects(:upload_script).once.returns('test_script.rb')
    stop_ost_services.stubs(:run_shell_command).once.returns(:data => {:exit_code => 42})

    stop_ost_services.process(deploy_data, ctx)
    ctx.expects(:report_and_update_status).never
  end

  it 'should upload target script and run it' do
    script_content = 'script content'
    target_file = '/tmp/stop_services.rb'
    stop_ost_services.stubs(:get_file).once.returns script_content
    stop_ost_services.expects(:upload_script).with(ctx, deploy_data.map{ |n| n['uid'] }, target_file, script_content).once
    stop_ost_services.expects(:run_shell_command).once.returns(:data => {:exit_code => 0})
    stop_ost_services.process(deploy_data, ctx)
  end

end

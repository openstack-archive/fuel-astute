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

require File.join(File.dirname(__FILE__), '../../spec_helper')

describe Astute::PostDeployPatching do
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
                         'cobbler' => {
                            'profile' => 'centos-x86_64'
                          }
                        },
                        {'uid' => '2',
                         'role' => 'compute'
                        }
                      ]
                    }

  let(:post_deploy_patching) { Astute::PostDeployPatching.new }

  it 'should run if upgrade/downgrade env' do
    post_deploy_patching.expects(:run_shell_command).once.returns(:data => {:exit_code => 0})
    post_deploy_patching.process(deploy_data, ctx)
  end

  it 'should not run if deploy new env' do
    deploy_data.first.delete('openstack_version_prev')
    post_deploy_patching.process(deploy_data, ctx)
    post_deploy_patching.expects(:run_shell_command).never

    post_deploy_patching.process(deploy_data, ctx)
  end

  it 'should not change deployment status if command fail' do
    post_deploy_patching.expects(:run_shell_command).once.returns(:data => {:exit_code => 1})
    ctx.expects(:report_and_update_status).never

    post_deploy_patching.process(deploy_data, ctx)
  end

  it 'should not change deployment status if shell exec using mcollective fail' do
    post_deploy_patching.expects(:run_shell_command).once.returns(:data => {})

    post_deploy_patching.process(deploy_data, ctx)
    ctx.expects(:report_and_update_status).never
  end

  it 'should special command' do
    post_deploy_patching.expects(:run_shell_command).with(
      ctx,
      ['1', '2'],
      regexp_matches(/post-deploy/),
      600
    ).once.returns(:data => {:exit_code => 0})

    post_deploy_patching.process(deploy_data, ctx)
  end

end
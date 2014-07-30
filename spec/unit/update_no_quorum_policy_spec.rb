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

describe Astute::UpdateNoQuorumPolicy do
  include SpecHelpers

  let(:ctx) do
    ctx = mock('context')
    ctx.stubs(:task_id)
    ctx.stubs(:reporter)
    ctx.stubs(:status).returns(1 => 'success', 2 => 'success')
    ctx
  end

  let(:deploy_data) { [
                        {'uid' => 1,
                         'role' => 'primary-controller',
                         'nodes' => [
                          {
                            'uid' => 1,
                            'slave_name' => 'node-1',
                            'role' => 'primary-controller'
                          },
                          {
                            'uid' => 2,
                            'slave_name' => 'node-2',
                            'role' => 'ceph-osd'
                          }
                         ]
                        },
                        {'uid' => 2,
                         'role' => 'ceph-osd',
                         'storage' => {
                            'objects_ceph' => true
                         }
                        }
                      ]
                    }

  let(:update_no_quorum_policy) { Astute::UpdateNoQuorumPolicy.new }

  it 'should run if deploy success' do
    update_no_quorum_policy.expects(:run_shell_command).once.returns(:data => {:exit_code => 0})
    update_no_quorum_policy.process(deploy_data, ctx)
  end

  it 'should run if deploy fail' do
    ctx.stubs(:status).returns(1 => 'error', 2 => 'success')
    update_no_quorum_policy.expects(:run_shell_command).once.returns(:data => {:exit_code => 0})

    update_no_quorum_policy.process(deploy_data, ctx)
  end

  it 'should not change deployment status if command fail' do
    update_no_quorum_policy.expects(:run_shell_command).once.returns(:data => {:exit_code => 1})

    update_no_quorum_policy.process(deploy_data, ctx)
    ctx.expects(:report_and_update_status).never
  end

  it 'should not change deployment status if mcollective fail' do
    update_no_quorum_policy.expects(:run_shell_command).once.returns(:data => {})

    update_no_quorum_policy.process(deploy_data, ctx)
    ctx.expects(:report_and_update_status).never
  end

  it 'should run only in primary-controller node' do
    update_no_quorum_policy.expects(:run_shell_command).once
                    .with(ctx, [1], anything)
                    .returns(:data => {:exit_code => 0})
    update_no_quorum_policy.process(deploy_data, ctx)
  end

end

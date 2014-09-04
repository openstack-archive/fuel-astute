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

describe Astute::RestartRadosgw do
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
                         'role' => 'controller',
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

  let(:restart_radosgw) { Astute::RestartRadosgw.new }

  it 'should run if deploy success' do
    restart_radosgw.expects(:run_shell_command).once.returns(:data => {:exit_code => 0})
    restart_radosgw.process(deploy_data, ctx)
  end

  it 'should run if deploy fail' do
    ctx.stubs(:status).returns(1 => 'error', 2 => 'success')
    restart_radosgw.expects(:run_shell_command).once.returns(:data => {:exit_code => 0})

    restart_radosgw.process(deploy_data, ctx)
  end

  it 'should not change deployment status if command fail' do
    restart_radosgw.expects(:run_shell_command).once.returns(:data => {:exit_code => 1})

    restart_radosgw.process(deploy_data, ctx)
    ctx.expects(:report_and_update_status).never
  end

  it 'should not change deployment status if mcollective fail' do
    restart_radosgw.expects(:run_shell_command).once.returns(:data => {})

    restart_radosgw.process(deploy_data, ctx)
    ctx.expects(:report_and_update_status).never
  end

  it 'should not run if no ceph node present' do
    deploy_data = [{'uid' => 1, 'role' => 'controller'}]
    restart_radosgw.expects(:run_shell_command).never

    restart_radosgw.process(deploy_data, ctx)
  end

  it 'should not run if objects_ceph is false' do
    deploy_data[1]['storage']['objects_ceph'] = false
    restart_radosgw.expects(:run_shell_command).never

    restart_radosgw.process(deploy_data, ctx)
  end

  it 'should run only in controller nodes' do
    restart_radosgw.expects(:run_shell_command).once
                    .with(ctx, [1], anything)
                    .returns(:data => {:exit_code => 0})
    restart_radosgw.process(deploy_data, ctx)
  end

end
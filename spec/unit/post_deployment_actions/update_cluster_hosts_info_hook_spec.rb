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

describe Astute::UpdateClusterHostsInfo do
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
                            'slave_name' => 'node-1'
                          },
                          {
                            'uid' => 2,
                            'slave_name' => 'node-2'
                          }
                         ]
                        },
                        {'uid' => 2,
                         'role' => 'compute'
                        }
                      ]
                    }

  let(:update_hosts) { Astute::UpdateClusterHostsInfo.new }

  it 'should run if deploy success' do
    update_hosts.expects(:upload_file).twice
    update_hosts.expects(:run_shell_command).twice.returns(:data => {:exit_code => 0})
    update_hosts.process(deploy_data, ctx)
  end

  it 'should run if deploy fail' do
    ctx.stubs(:status).returns(1 => 'error', 2 => 'success')
    update_hosts.expects(:upload_file).twice
    update_hosts.expects(:run_shell_command).twice.returns(:data => {:exit_code => 0})

    update_hosts.process(deploy_data, ctx)
  end

  it 'should not change deployment status if command fail' do
    update_hosts.expects(:upload_file).twice
    update_hosts.expects(:run_shell_command).twice.returns(:data => {:exit_code => 1})

    update_hosts.process(deploy_data, ctx)
    ctx.expects(:report_and_update_status).never
  end

  it 'should not change deployment status if shell exec using mcollective fail' do
    update_hosts.expects(:upload_file).twice
    update_hosts.expects(:run_shell_command).twice.returns(:data => {})

    update_hosts.process(deploy_data, ctx)
    ctx.expects(:report_and_update_status).never
  end

  it 'should run in all cluster nodes' do
    deploy_data.first['nodes'] += [{'uid' => 3, 'slave_name' => 'node-3'}]
    update_hosts.expects(:upload_file).with(1, anything, ctx)
    update_hosts.expects(:upload_file).with(2, anything, ctx)
    update_hosts.expects(:upload_file).with(3, anything, ctx)
    update_hosts.expects(:run_shell_command)
                    .with(ctx, [1], anything)
                    .returns(:data => {:exit_code => 0})
    update_hosts.expects(:run_shell_command)
                    .with(ctx, [2], anything)
                    .returns(:data => {:exit_code => 0})
    update_hosts.expects(:run_shell_command)
                    .with(ctx, [3], anything)
                    .returns(:data => {:exit_code => 0})
    update_hosts.process(deploy_data, ctx)
  end

  describe '#upload_file' do

    let(:node_uid) { 1 }

    before(:each) do
      mock_rpcclient([{'uid' => node_uid}])
    end

    it 'should not raise timeout error if mcollective runs out of the timeout' do
      Astute::MClient.any_instance.stubs(:mc_send).raises(Astute::MClientTimeout)
      expect { update_hosts.send(:upload_file, node_uid, "", ctx) }.to_not raise_error
    end

    it 'should not raise mcollective error if it occurred' do
      Astute::MClient.any_instance.stubs(:mc_send).raises(Astute::MClientError)
      expect { update_hosts.send(:upload_file, node_uid, "", ctx) }.to_not raise_error
    end
  end

end
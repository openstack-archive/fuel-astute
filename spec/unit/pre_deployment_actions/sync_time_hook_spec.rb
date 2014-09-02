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

describe Astute::SyncTime do
  include SpecHelpers

  let(:ctx) do
    tctx = mock_ctx
    tctx.stubs(:status).returns({})
    tctx
  end

  let(:deploy_data) { [{'uid' => 1, 'deployment_id' => 1}, {'uid' => 2}] }
  let(:sync_time) { Astute::SyncTime.new }

  it 'should sync time between cluster nodes' do
    sync_time.expects(:run_shell_command_remotely).with(
      ctx,
      [1,2],
      "ntpdate -u $(egrep '^server' /etc/ntp.conf | sed '/^#/d' | awk '{print $2}')"
      ).returns(true)
    sync_time.process(deploy_data, ctx)
  end

  it 'should not raise exception if fail' do
    sync_time.stubs(:run_shell_command_remotely).returns(false)
    expect { sync_time.process(deploy_data, ctx) }.to_not raise_error
  end

  it 'should try to sync several times if fail' do
    sync_time.stubs(:run_shell_command_remotely).returns(false)
            .then.returns(true).twice

    sync_time.process(deploy_data, ctx)
  end

end
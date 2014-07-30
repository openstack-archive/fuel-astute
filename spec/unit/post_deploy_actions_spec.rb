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

describe Astute::PostDeployActions do
  include SpecHelpers

  let(:deploy_data) {[]}
  let(:ctx) { mock }
  let(:post_deploy_actions) { Astute::PostDeployActions.new(deploy_data, ctx) }

  it 'should run post hooks' do
    Astute::UpdateNoQuorumPolicy.any_instance.expects(:process)
                                             .with(deploy_data, ctx)
    Astute::UploadCirrosImage.any_instance.expects(:process)
                                          .with(deploy_data, ctx)
    Astute::RestartRadosgw.any_instance.expects(:process)
                                       .with(deploy_data, ctx)
    Astute::UpdateClusterHostsInfo.any_instance.expects(:process)
                                               .with(deploy_data, ctx)

    post_deploy_actions.process
  end
end

describe Astute::PostDeployAction do
  include SpecHelpers

  let(:ctx) { mock_ctx }
  let(:node_uids) { [1] }
  let(:pda_example) { Astute::PostDeployAction.new }

  before(:each) { mock_rpcclient([{'uid' => 1}]) }

  it 'should not raise timeout error if mcollective runs out of the timeout' do
    Astute::MClient.any_instance.stubs(:mc_send).raises(Astute::MClientTimeout)
    expect(pda_example.run_shell_command(ctx, node_uids, "test command")).to eql({:data => {}})
  end

  it 'should not raise mcollective error if it occurred' do
    Astute::MClient.any_instance.stubs(:mc_send).raises(Astute::MClientError)
    expect(pda_example.run_shell_command(ctx, node_uids, "test command")).to eql({:data => {}})
  end

end

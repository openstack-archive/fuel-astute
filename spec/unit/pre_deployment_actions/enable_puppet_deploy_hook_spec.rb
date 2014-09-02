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

describe Astute::EnablePuppetDeploy do
  include SpecHelpers

  let(:ctx) do
    tctx = mock_ctx
    tctx.stubs(:status).returns({})
    tctx
  end

  let(:mclient) do
    mclient = mock_rpcclient(deploy_data)
    Astute::MClient.any_instance.stubs(:rpcclient).returns(mclient)
    Astute::MClient.any_instance.stubs(:log_result).returns(mclient)
    Astute::MClient.any_instance.stubs(:check_results_with_retries).returns(mclient)
    mclient
  end

  let(:deploy_data) { [{'uid' => 1, 'deployment_id' => 1}, {'uid' => 2}] }
  let(:enable_puppet_deploy) { Astute::EnablePuppetDeploy.new }

  it 'should enable puppet for all nodes' do
    mclient.expects(:enable)
    enable_puppet_deploy.process(deploy_data, ctx)
  end

end
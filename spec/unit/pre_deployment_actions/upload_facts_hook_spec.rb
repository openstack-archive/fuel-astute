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

describe Astute::UploadFacts do
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
                        }
                      ]
                    }

  let(:upload_facts) { Astute::UploadFacts.new }

  let(:mclient) do
    mclient = mock_rpcclient(deploy_data)
    Astute::MClient.any_instance.stubs(:rpcclient).returns(mclient)
    Astute::MClient.any_instance.stubs(:log_result).returns(mclient)
    Astute::MClient.any_instance.stubs(:check_results_with_retries).returns(mclient)
    mclient
  end

  it 'should upload facts using YAML format to nodes in <role>.yaml file' do
    mclient.expects(:upload).with(
      :path =>'/etc/controller.yaml',
      :content => deploy_data.first.to_yaml,
      :overwrite => true,
      :parents => true,
      :permissions => '0600'
    )

    upload_facts.process(deploy_data, ctx)
  end

end
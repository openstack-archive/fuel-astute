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

describe Astute::UploadSshKeys do
  include SpecHelpers

  around(:each) do |example|
    old_puppet_ssh_keys = Astute.config.PUPPET_SSH_KEYS
    example.run
    Astute.config.PUPPET_SSH_KEYS = old_puppet_ssh_keys
  end

  before(:each) do
    Astute.config.PUPPET_SSH_KEYS = ['nova']
  end

  let(:ctx) do
    tctx = mock_ctx
    tctx.stubs(:status).returns({})
    tctx
  end

  let(:deploy_data) { [{'uid' => 1, 'deployment_id' => 1}, {'uid' => 2}] }
  let(:upload_ssh_keys) { Astute::UploadSshKeys.new }

  it "should upload ssh keys using mcollective client 'uploadfile'" do
    mclient = mock_rpcclient(deploy_data)
    Astute::MClient.any_instance.stubs(:rpcclient).returns(mclient)
    Astute::MClient.any_instance.stubs(:log_result).returns(mclient)
    Astute::MClient.any_instance.stubs(:check_results_with_retries).returns(mclient)

    File.stubs(:read).returns("private key").then.returns("public key")
    mclient.expects(:upload).with(:path => File.join(Astute.config.PUPPET_SSH_KEYS_DIR, 'nova', 'nova'),
                                  :content => "private key",
                                  :user_owner => 'root',
                                  :group_owner => 'root',
                                  :permissions => '0600',
                                  :dir_permissions => '0700',
                                  :overwrite => true,
                                  :parents => true
                                 )
    mclient.expects(:upload).with(:path => File.join(Astute.config.PUPPET_SSH_KEYS_DIR, 'nova', 'nova.pub'),
                                  :content => "public key",
                                  :user_owner => 'root',
                                  :group_owner => 'root',
                                  :permissions => '0600',
                                  :dir_permissions => '0700',
                                  :overwrite => true,
                                  :parents => true
                                 )
    upload_ssh_keys.process(deploy_data, ctx)
  end

end
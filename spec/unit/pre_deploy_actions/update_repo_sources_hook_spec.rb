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

describe Astute::UpdateRepoSources do
  include SpecHelpers

  before(:each) do
    Astute.config.PUPPET_SSH_KEYS = ['nova']
  end

  let(:ctx) do
    tctx = mock_ctx
    tctx.stubs(:status).returns({})
    tctx
  end

  let(:mclient) do
    mclient = mock_rpcclient(nodes)
    Astute::MClient.any_instance.stubs(:rpcclient).returns(mclient)
    Astute::MClient.any_instance.stubs(:log_result).returns(mclient)
    Astute::MClient.any_instance.stubs(:check_results_with_retries).returns(mclient)
    mclient
  end

  let(:nodes) do
    [
      {'uid' => 1,
       'deployment_id' => 1,
       'cobbler' => {
          'profile' => 'centos-x86_64'
       },
       'repo_metadata' => {
          'Nailgun' => 'http://10.20.0.2:8080/centos/fuelweb/x86_64/',
       }
      },
      {'uid' => 2}
    ]
  end
  let(:update_repo_sources) { Astute::UpdateRepoSources.new }

  around(:each) do |example|
    old_ssh_keys_dir = Astute.config.PUPPET_SSH_KEYS_DIR
    example.run
    Astute.config.PUPPET_SSH_KEYS_DIR = old_ssh_keys_dir
  end

  context 'source configuration generation' do
    before(:each) do
      update_repo_sources.stubs(:regenerate_metadata)
    end

    it 'should generate correct config for centos' do
      content = ["[nailgun]",
                 "name=Nailgun",
                 "baseurl=http://10.20.0.2:8080/centos/fuelweb/x86_64/",
                 "gpgcheck=0"].join("\n")

      update_repo_sources.expects(:upload_repo_source).with(ctx, nodes, content)
      update_repo_sources.process(nodes, ctx)
    end

    it 'should generate correct config for ubuntu' do
      nodes.first['cobbler']['profile'] = 'ubuntu_1204_x86_64'
      nodes.first['repo_metadata']['Nailgun'] =
          'http://10.20.0.2:8080/ubuntu/fuelweb/x86_64 precise main'
      content = "deb http://10.20.0.2:8080/ubuntu/fuelweb/x86_64 precise main"

      update_repo_sources.expects(:upload_repo_source).with(ctx, nodes, content)
      update_repo_sources.process(nodes, ctx)
    end

    it 'should raise error if os not recognized' do
      nodes.first['cobbler']['profile'] = 'unknown'

      expect {update_repo_sources.process(nodes, ctx)}.to raise_error(
        Astute::DeploymentEngineError, /Unknown system/)
    end
  end # source configuration generation

  context 'new source configuration uploading' do

    let(:repo_content) { "repo conf" }

    before(:each) do
      update_repo_sources.stubs(:generate_repo_source).returns(repo_content)
      update_repo_sources.stubs(:regenerate_metadata)
    end

    it 'should upload config in correct place for centos' do
      mclient.expects(:upload).with(:path => '/etc/yum.repos.d/nailgun.repo',
                            :content => repo_content,
                            :user_owner => 'root',
                            :group_owner => 'root',
                            :permissions => '0644',
                            :dir_permissions => '0755',
                            :overwrite => true,
                            :parents => true
                           )
      update_repo_sources.process(nodes, ctx)
    end

    it 'should upload config in correct place for ubuntu' do
      nodes.first['cobbler']['profile'] = 'ubuntu_1204_x86_64'

      mclient.expects(:upload).with(:path => '/etc/apt/sources.list',
                    :content => repo_content,
                    :user_owner => 'root',
                    :group_owner => 'root',
                    :permissions => '0644',
                    :dir_permissions => '0755',
                    :overwrite => true,
                    :parents => true
                   )
      update_repo_sources.process(nodes, ctx)
    end
  end #new source configuration uploading

  context 'metadata regeneration' do

    let(:fail_return) { [{:data => {:exit_code => 1}}] }

    before(:each) do
      update_repo_sources.stubs(:generate_repo_source)
      update_repo_sources.stubs(:upload_repo_source)
    end

    let(:success_return) { [{:data => {:exit_code => 0}}] }

    it 'should regenerate metadata for centos' do
      mclient.expects(:execute).with(:cmd => 'yum clean all').returns(success_return)
      update_repo_sources.process(nodes, ctx)
    end

    it 'should regenerate metadata for ubuntu' do
      nodes.first['cobbler']['profile'] = 'ubuntu_1204_x86_64'
      mclient.expects(:execute).with(:cmd => 'apt-get clean; apt-get update').returns(success_return)
      update_repo_sources.process(nodes, ctx)
    end

    it 'should raise error if metadata not updated' do
      nodes.first['cobbler']['profile'] = 'ubuntu_1204_x86_64'
      mclient.expects(:execute).with(:cmd => 'apt-get clean; apt-get update').returns(fail_return).times(Astute.config[:MC_RETRIES])
      expect { update_repo_sources.process(nodes, ctx) }.to raise_error(Astute::DeploymentEngineError,
                /Run command:/)
    end

    it 'should retry metadata update several time if get error' do
      nodes.first['cobbler']['profile'] = 'ubuntu_1204_x86_64'
      mclient.expects(:execute).with(:cmd => 'apt-get clean; apt-get update').returns(fail_return)
                               .then.returns(success_return).twice
      update_repo_sources.process(nodes, ctx)
    end
  end #'metadata regeneration'

end
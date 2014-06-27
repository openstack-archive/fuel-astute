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
require 'tmpdir'

describe Astute::DeploymentEngine do
  include SpecHelpers

  class Engine < Astute::DeploymentEngine; end

  let(:ctx) { mock_ctx }

  describe '#new' do
    it 'should not be avaliable to instantiation' do
      expect { Astute::DeploymentEngine.new(ctx) }.to raise_exception(/Instantiation of this superclass is not allowed/)
    end

    it 'should be avaliable as superclass' do
      expect { Engine.new(ctx) }.to be_true
    end
  end

  let(:deployer) { Engine.new(ctx) }

  describe '#deploy' do

    before(:each) do
      deployer.stubs(:generate_ssh_keys)
      deployer.stubs(:upload_ssh_keys)
      deployer.stubs(:sync_puppet_manifests)
      deployer.stubs(:enable_puppet_deploy)
      deployer.stubs(:update_repo_sources)
      deployer.stubs(:deploy_piece)
    end

    it 'should generate and upload ssh keys' do
      nodes = [{'uid' => 1, 'deployment_id' => 1}, {'uid' => 2}, {'uid' => 1}]

      deployer.expects(:generate_ssh_keys).with(nodes.first['deployment_id'])
      deployer.expects(:upload_ssh_keys).with([1,2], nodes.first['deployment_id']).returns()
      deployer.expects(:sync_puppet_manifests).with([{'uid' => 1, 'deployment_id' => 1}, {'uid' => 2}])

      deployer.deploy(nodes)
    end

    it 'should setup packages repositories' do
      nodes = [
        {'uid' => 1,
         'deployment_id' => 1,
         'repo_metadata' => {
            'Nailgun' => 'http://10.20.0.2:8080/centos/fuelweb/x86_64/'
         }
        },
        {'uid' => 2},
        {'uid' => 1}
      ]
      uniq_nodes = nodes[0..-2]

      deployer.expects(:update_repo_sources).with(uniq_nodes)

      deployer.deploy(nodes)
    end

    it 'should enable puppet for all nodes' do
      nodes = [{'uid' => 1, 'deployment_id' => 1}, {'uid' => 2}, {'uid' => 1}]


      deployer.expects(:enable_puppet_deploy).with([1,2]).returns()

      deployer.deploy(nodes)
    end

    it 'deploy nodes by order' do
      nodes = [{'uid' => 1, 'priority' => 10}, {'uid' => 2, 'priority' => 0}, {'uid' => 1, 'priority' => 15}]

      deployer.expects(:deploy_piece).with([{'uid' => 2, 'priority' => 0}])
      deployer.expects(:deploy_piece).with([{'uid' => 1, 'priority' => 10}])
      deployer.expects(:deploy_piece).with([{'uid' => 1, 'priority' => 15}])

      deployer.deploy(nodes)
    end

    it 'nodes with same priority should be deploy at parallel' do
      nodes = [{'uid' => 1, 'priority' => 10}, {'uid' => 2, 'priority' => 0}, {'uid' => 3, 'priority' => 10}]

      deployer.expects(:deploy_piece).with([{'uid' => 2, 'priority' => 0}])
      deployer.expects(:deploy_piece).with([{"uid"=>1, "priority"=>10}, {"uid"=>3, "priority"=>10}])

      deployer.deploy(nodes)
    end

    it 'node with several roles with same priority should not run at parallel' do
      nodes = [
        {'uid' => 1, 'priority' => 10, 'role' => 'compute'},
        {'uid' => 2, 'priority' => 0, 'role' => 'primary-controller'},
        {'uid' => 1, 'priority' => 10, 'role' => 'cinder'}
      ]

      deployer.expects(:deploy_piece).with([{'uid' => 2, 'priority' => 0, 'role' => 'primary-controller'}])
      deployer.expects(:deploy_piece).with([{'uid' => 1, 'priority' => 10, 'role' => 'compute'}])
      deployer.expects(:deploy_piece).with([{'uid' => 1, 'priority' => 10, 'role' => 'cinder'}])

      deployer.deploy(nodes)
    end

    it 'node with several roles with same priority should not run at parallel, but diffirent nodes should' do
      nodes = [
        {'uid' => 1, 'priority' => 10, 'role' => 'compute'},
        {'uid' => 3, 'priority' => 10, 'role' => 'compute'},
        {'uid' => 2, 'priority' => 0, 'role' => 'primary-controller'},
        {'uid' => 1, 'priority' => 10, 'role' => 'cinder'}
      ]

      deployer.expects(:deploy_piece).with([{'uid' => 2, 'priority' => 0, 'role' => 'primary-controller'}])
      deployer.expects(:deploy_piece).with([
        {'uid' => 1, 'priority' => 10, 'role' => 'compute'},
        {'uid' => 3, 'priority' => 10, 'role' => 'compute'}
      ])
      deployer.expects(:deploy_piece).with([{'uid' => 1, 'priority' => 10, 'role' => 'cinder'}])

      deployer.deploy(nodes)
    end

    context 'limits' do
      around(:each) do |example|
        old_value = Astute.config.MAX_NODES_PER_CALL
        example.run
        Astute.config.MAX_NODES_PER_CALL = old_value
      end

      it 'number of nodes running in parallel should be limit' do
        Astute.config.MAX_NODES_PER_CALL = 1
        deployer.stubs(:generate_ssh_keys)
        deployer.stubs(:upload_ssh_keys)
        deployer.stubs(:sync_puppet_manifests)

        nodes = [
          {'uid' => 1, 'priority' => 10, 'role' => 'compute'},
          {'uid' => 3, 'priority' => 10, 'role' => 'compute'},
          {'uid' => 2, 'priority' => 0, 'role' => 'primary-controller'},
          {'uid' => 1, 'priority' => 10, 'role' => 'cinder'}
        ]

        deployer.expects(:deploy_piece).with([{'uid' => 2, 'priority' => 0, 'role' => 'primary-controller'}])
        deployer.expects(:deploy_piece).with([{'uid' => 1, 'priority' => 10, 'role' => 'compute'}])
        deployer.expects(:deploy_piece).with([{'uid' => 3, 'priority' => 10, 'role' => 'compute'}])
        deployer.expects(:deploy_piece).with([{'uid' => 1, 'priority' => 10, 'role' => 'cinder'}])

        deployer.deploy(nodes)
      end
    end

    it 'should raise error if deployment list is empty' do
      expect { deployer.deploy([]) }.to raise_error('Deployment info are not provided!')
    end

  end

  describe '#sync_puppet_manifests' do
    before(:each) do
      deployer.stubs(:deploy_piece)
      deployer.stubs(:generate_ssh_keys)
      deployer.stubs(:upload_ssh_keys)
      deployer.stubs(:enable_puppet_deploy)
    end

    let(:nodes) { [
                    {'uid' => 1,
                     'deployment_id' => 1,
                     'master_ip' => '10.20.0.2',
                     'puppet_modules_source' => 'rsync://10.20.0.2:/puppet/modules/',
                     'puppet_manifests_source' => 'rsync://10.20.0.2:/puppet/manifests/'
                    },
                    {'uid' => 2}
                  ]
                }
    let(:mclient) do
      mclient = mock_rpcclient(nodes)
      Astute::MClient.any_instance.stubs(:rpcclient).returns(mclient)
      Astute::MClient.any_instance.stubs(:log_result).returns(mclient)
      Astute::MClient.any_instance.stubs(:check_results_with_retries).returns(mclient)
      mclient
    end
    let(:master_ip) { nodes.first['master_ip'] }

    it "should sync puppet modules and manifests mcollective client 'puppetsync'" do
      mclient.expects(:rsync).with(:modules_source => "rsync://10.20.0.2:/puppet/modules/",
                                   :manifests_source => "rsync://10.20.0.2:/puppet/manifests/"
                                   )
      deployer.deploy(nodes)
    end

    it 'should able to customize path for puppet modules and manifests' do
      modules_source = 'rsync://10.20.0.2:/puppet/vX/modules/'
      manifests_source = 'rsync://10.20.0.2:/puppet/vX/manifests/'
      nodes.first['puppet_modules_source'] = modules_source
      nodes.first['puppet_manifests_source'] = manifests_source
      mclient.expects(:rsync).with(:modules_source => modules_source,
                                   :manifests_source => manifests_source
                                   )
      deployer.deploy(nodes)
    end


    context 'retry sync if mcollective raise error and' do
      it 'raise error if retry fail SYNC_RETRIES times' do
        mclient.stubs(:rsync)
        Astute::MClient.any_instance.stubs(:check_results_with_retries)
                                    .raises(Astute::MClientError)
                                    .times(Astute::DeploymentEngine::SYNC_RETRIES)
        expect { deployer.deploy(nodes) }.to raise_error(Astute::MClientError)
      end

      it 'not raise error if mcollective return success less than SYNC_RETRIES attempts' do
        mclient.stubs(:rsync)
        Astute::MClient.any_instance.stubs(:check_results_with_retries)
                                    .raises(Astute::MClientError)
                                    .then.returns("")
        expect { deployer.deploy(nodes) }.to_not raise_error(Astute::MClientError)
      end
    end

    it 'should raise exception if modules/manifests schema of uri is not equal' do
      nodes.first['puppet_manifests_source'] = 'rsync://10.20.0.2:/puppet/vX/modules/'
      nodes.first['puppet_manifests_source'] = 'http://10.20.0.2:/puppet/vX/manifests/'
      expect { deployer.deploy(nodes) }.to raise_error(Astute::DeploymentEngineError,
          /Scheme for puppet_modules_source 'rsync' and puppet_manifests_source/)
    end

    it 'should raise exception if modules/manifests source uri is incorrect' do
      nodes.first['puppet_manifests_source'] = ':/puppet/modules/'
      expect { deployer.deploy(nodes) }.to raise_error(Astute::DeploymentEngineError,
                                                         /bad URI/)
    end

    it 'should raise exception if schema of uri is incorrect' do
      nodes.first['puppet_modules_source'] = 'http2://localhost/puppet/modules/'
      nodes.first['puppet_manifests_source'] = 'http2://localhost/puppet/manifests/'
      mclient.expects(:rsync).never
      expect { deployer.deploy(nodes) }.to raise_error(Astute::DeploymentEngineError,
                                                         /Unknown scheme /)
    end
  end

  describe '#update_repo_sources' do
    before(:each) do
      deployer.stubs(:generate_ssh_keys)
      deployer.stubs(:upload_ssh_keys)
      deployer.stubs(:sync_puppet_manifests)
      deployer.stubs(:enable_puppet_deploy)
      deployer.stubs(:deploy_piece)
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

    let(:mclient) do
      mclient = mock_rpcclient(nodes)
      Astute::MClient.any_instance.stubs(:rpcclient).returns(mclient)
      Astute::MClient.any_instance.stubs(:log_result).returns(mclient)
      Astute::MClient.any_instance.stubs(:check_results_with_retries).returns(mclient)
      mclient
    end

    context 'source configuration generation' do
      before(:each) do
        deployer.stubs(:regenerate_metadata)
      end

      it 'should generate correct config for centos' do
        content = ["[nailgun]",
                   "name=Nailgun",
                   "baseurl=http://10.20.0.2:8080/centos/fuelweb/x86_64/",
                   "gpgcheck=0"].join("\n")

        deployer.expects(:upload_repo_source).with(nodes, content)
        deployer.deploy(nodes)
      end

      it 'should generate correct config for ubuntu' do
        nodes.first['cobbler']['profile'] = 'ubuntu_1204_x86_64'
        nodes.first['repo_metadata']['Nailgun'] =
            'http://10.20.0.2:8080/ubuntu/fuelweb/x86_64 precise main'
        content = "deb http://10.20.0.2:8080/ubuntu/fuelweb/x86_64 precise main"

        deployer.expects(:upload_repo_source).with(nodes, content)
        deployer.deploy(nodes)
      end

      it 'should raise error if os not recognized' do
        nodes.first['cobbler']['profile'] = 'unknown'

        expect {deployer.deploy(nodes)}.to raise_error(Astute::DeploymentEngineError,
                                                         /Unknown system/)
      end
    end # source configuration generation

    context 'new source configuration uploading' do

      let(:repo_content) { "repo conf" }

      before(:each) do
        deployer.stubs(:generate_repo_source).returns(repo_content)
        deployer.stubs(:regenerate_metadata)
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
        deployer.deploy(nodes)
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
        deployer.deploy(nodes)
      end
    end #new source configuration uploading

    context 'metadata regeneration' do

      let(:fail_return) { [{:data => {:exit_code => 1}}] }

      before(:each) do
        deployer.stubs(:generate_repo_source)
        deployer.stubs(:upload_repo_source)
      end

      let(:success_return) { [{:data => {:exit_code => 0}}] }

      it 'should regenerate metadata for centos' do
        mclient.expects(:execute).with(:cmd => 'yum clean all').returns(success_return)
        deployer.deploy(nodes)
      end

      it 'should regenerate metadata for ubuntu' do
        nodes.first['cobbler']['profile'] = 'ubuntu_1204_x86_64'
        mclient.expects(:execute).with(:cmd => 'apt-get clean; apt-get update').returns(success_return)
        deployer.deploy(nodes)
      end

      it 'should raise error if metadata not updated' do
        nodes.first['cobbler']['profile'] = 'ubuntu_1204_x86_64'
        mclient.expects(:execute).with(:cmd => 'apt-get clean; apt-get update').returns(fail_return).times(5)
        expect { deployer.deploy(nodes) }.to raise_error(Astute::DeploymentEngineError,
                  /Run command:/)
      end

      it 'should retry metadata update several time if get error' do
        nodes.first['cobbler']['profile'] = 'ubuntu_1204_x86_64'
        mclient.expects(:execute).with(:cmd => 'apt-get clean; apt-get update').returns(fail_return)
                                 .then.returns(success_return).twice
        deployer.deploy(nodes)
      end
    end #'metadata regeneration'
  end # update_repo_sources

  describe '#generation and uploading of ssh keys' do
    before(:each) do
      Astute.config.PUPPET_SSH_KEYS = ['nova']
      deployer.stubs(:deploy_piece)
      deployer.stubs(:sync_puppet_manifests)
      deployer.stubs(:enable_puppet_deploy)
    end

    let(:nodes) { [{'uid' => 1, 'deployment_id' => 1}, {'uid' => 2}] }

    it 'should use Astute.config to get the ssh names that need to generate' do
      deployer.expects(:generate_ssh_keys).with(nodes.first['deployment_id'])
      deployer.expects(:upload_ssh_keys).with([1, 2], nodes.first['deployment_id'])
      deployer.deploy(nodes)
    end

    it 'should raise error if deployment_id is not set' do
      nodes = [{'uid' => 1}, {'uid' => 2}]
      expect { deployer.deploy(nodes) }.to raise_error('Deployment_id is missing')
    end

    context 'generation of ssh keys' do
      before(:each) do
        deployer.stubs(:upload_ssh_keys).with([1, 2], nodes.first['deployment_id'])
      end

      it 'should save files in correct place: KEY_DIR/<name of key>/' do
        Engine.any_instance.stubs(:run_system_command).returns([0, "", ""])

        Dir.mktmpdir do |temp_dir|
          Astute::DeploymentEngine.const_set 'KEY_DIR', temp_dir
          deployer.deploy(nodes)

          expect { File.directory? File.join(temp_dir, 'nova') }.to be_true
        end
      end

      it 'should raise error if directory for key was not created' do
        FileUtils.stubs(:mkdir_p).returns(false)
        File.stubs(:directory?).returns(false)

        expect { deployer.deploy(nodes) }.to raise_error(Astute::DeploymentEngineError,
                                                         /Could not create directory/)
      end

      it 'should raise error if ssh key generation fail' do
        FileUtils.stubs(:mkdir_p).returns(true)
        File.stubs(:directory?).returns(true)
        Engine.any_instance.stubs(:run_system_command).returns([1, "", ""])

        expect { deployer.deploy(nodes) }.to raise_error(Astute::DeploymentEngineError,
                                                         /Could not generate ssh key! Command:/)
      end

      it 'should raise error if ssh key generation command not find' do
        FileUtils.stubs(:mkdir_p).returns(true)
        File.stubs(:directory?).returns(true)
        Engine.any_instance.stubs(:run_system_command).returns([127, "Command not found", ""])

        expect { deployer.deploy(nodes) }.to raise_error(Astute::DeploymentEngineError,
                                                         /Command not found/)
      end

      it 'should run ssh key generation with correct command' do
        FileUtils.stubs(:mkdir_p).returns(true)
        File.stubs(:directory?).returns(true)

        key_path = File.join(Engine::KEY_DIR, nodes.first['deployment_id'].to_s, 'nova', 'nova')
        cmd = "ssh-keygen -b 2048 -t rsa -N '' -f #{key_path} 2>&1"
        Engine.any_instance.expects(:run_system_command).with(cmd).returns([0, "", ""])

        deployer.deploy(nodes)
      end

      it 'should not overwrite files' do
        Dir.mktmpdir do |temp_dir|
          Astute::DeploymentEngine.const_set 'KEY_DIR', temp_dir
          key_path = File.join(temp_dir,'nova', 'nova')
          FileUtils.mkdir_p File.join(temp_dir,'nova')
          File.open(key_path, 'w') { |file| file.write("say no overwrite") }
          deployer.deploy(nodes)

          expect { File.exist? File.join(key_path, 'nova', 'nova') }.to be_true
          expect { File.read File.join(key_path, 'nova', 'nova') == "say no overwrite" }.to be_true
        end
      end

      it 'should check next key if find existing' do
        Astute.config.PUPPET_SSH_KEYS = ['nova', 'test']
        nova_key_path = File.join(Engine::KEY_DIR, nodes.first['deployment_id'].to_s, 'nova', 'nova')
        test_key_path = File.join(Engine::KEY_DIR, nodes.first['deployment_id'].to_s, 'test', 'test')

        FileUtils.stubs(:mkdir_p).returns(true).twice
        File.stubs(:directory?).returns(true).twice

        File.stubs(:exist?).with(nova_key_path).returns(true)
        File.stubs(:exist?).with(test_key_path).returns(false)

        Engine.any_instance.expects(:run_system_command).returns([0, "", ""])

        deployer.deploy(nodes)
      end
    end # end context

    context 'upload ssh keys' do
      before(:each) do
        deployer.stubs(:generate_ssh_keys)
      end

      it "should upload ssh keys using mcollective client 'uploadfile'" do
        mclient = mock_rpcclient(nodes)
        Astute::MClient.any_instance.stubs(:rpcclient).returns(mclient)
        Astute::MClient.any_instance.stubs(:log_result).returns(mclient)
        Astute::MClient.any_instance.stubs(:check_results_with_retries).returns(mclient)

        File.stubs(:read).returns("private key").then.returns("public key")
        mclient.expects(:upload).with(:path => File.join(Engine::KEY_DIR, 'nova', 'nova'),
                                      :content => "private key",
                                      :user_owner => 'root',
                                      :group_owner => 'root',
                                      :permissions => '0600',
                                      :dir_permissions => '0700',
                                      :overwrite => true,
                                      :parents => true
                                     )
        mclient.expects(:upload).with(:path => File.join(Engine::KEY_DIR, 'nova', 'nova.pub'),
                                      :content => "public key",
                                      :user_owner => 'root',
                                      :group_owner => 'root',
                                      :permissions => '0600',
                                      :dir_permissions => '0700',
                                      :overwrite => true,
                                      :parents => true
                                     )
        deployer.deploy(nodes)
      end
    end # context
  end # describe
end

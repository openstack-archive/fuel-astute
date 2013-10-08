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
    it 'should generate and upload ssh keys' do
      nodes = [{'uid' => 1, 'deployment_id' => 1}, {'uid' => 2}, {'uid' => 1}]
      deployer.stubs(:deploy_piece)
      
      deployer.expects(:generate_and_upload_ssh_keys).with([1,2], nodes.first['deployment_id'])
      
      deployer.deploy(nodes)
    end
    
    it 'deploy nodes by order' do
      deployer.stubs(:generate_and_upload_ssh_keys)
      nodes = [{'uid' => 1, 'priority' => 10}, {'uid' => 2, 'priority' => 0}, {'uid' => 1, 'priority' => 15}]
      
      deployer.expects(:deploy_piece).with([{'uid' => 2, 'priority' => 0}])
      deployer.expects(:deploy_piece).with([{'uid' => 1, 'priority' => 10}])
      deployer.expects(:deploy_piece).with([{'uid' => 1, 'priority' => 15}])
      
      deployer.deploy(nodes)
    end
    
    it 'nodes with same priority should be deploy at parallel' do
      deployer.stubs(:generate_and_upload_ssh_keys)
      nodes = [{'uid' => 1, 'priority' => 10}, {'uid' => 2, 'priority' => 0}, {'uid' => 3, 'priority' => 10}]
      
      deployer.expects(:deploy_piece).with([{'uid' => 2, 'priority' => 0}])
      deployer.expects(:deploy_piece).with([{"uid"=>1, "priority"=>10}, {"uid"=>3, "priority"=>10}])
      
      deployer.deploy(nodes)
    end
    
    it 'node with several roles with same priority should not run at parallel' do
      deployer.stubs(:generate_and_upload_ssh_keys)
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
      deployer.stubs(:generate_and_upload_ssh_keys)
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
    
    it 'should raise error if deployment list is empty' do
      expect { deployer.deploy([]) }.to raise_error('Deployment info are not provided!')
    end
    
  end

  describe '#generate_and_upload_ssh_keys' do
    before(:each) do
      Astute.config.PUPPET_SSH_KEYS = ['nova']
      deployer.stubs(:deploy_piece)
    end
    
    let(:nodes) { [{'uid' => 1, 'deployment_id' => 1}, {'uid' => 2}] }
    
    it 'should use Astute.config to get the ssh names that need to generate' do
      deployer.expects(:generate_ssh_key).with('nova', nodes.first['deployment_id'])
      deployer.expects(:upload_ssh_key).with([1, 2], 'nova', nodes.first['deployment_id'])
      deployer.deploy(nodes)
    end
    
    it 'should raise error if deployment_id is not set' do
      nodes = [{'uid' => 1}, {'uid' => 2}]
      expect { deployer.deploy(nodes) }.to raise_error('Deployment_id is missing')
    end
    
    context 'generation of ssh keys' do
      before(:each) do
        deployer.stubs(:upload_ssh_key).with([1, 2], 'nova', nodes.first['deployment_id'])
      end
    
      it 'should save files in correct place: KEY_DIR/<name of key>/' do
        Engine.any_instance.stubs(:system).returns(true)
      
        Dir.mktmpdir do |temp_dir|
          Astute::DeploymentEngine.const_set 'KEY_DIR', temp_dir
          deployer.deploy(nodes)
        
          expect { File.directory? File.join(temp_dir, 'nova') }.to be_true
        end
      end
    
      it 'should raise error if ssh key generation fail' do
        FileUtils.stubs(:mkdir_p).returns(true)
        Engine.any_instance.stubs(:system).returns(false)
        
        expect { deployer.deploy(nodes) }.to raise_error('Could not generate ssh key!')
      end
      
      it 'should raise error if ssh key generation command not find' do
        FileUtils.stubs(:mkdir_p).returns(true)
        Engine.any_instance.stubs(:system).returns(nil)
        
        expect { deployer.deploy(nodes) }.to raise_error('Could not generate ssh key!')
      end
      
      it 'should run ssh key generation with correct command' do
        FileUtils.stubs(:mkdir_p).returns(true)
        key_path = File.join(Engine::KEY_DIR, nodes.first['deployment_id'].to_s, 'nova', 'nova')
        Engine.any_instance.expects(:system).with("ssh-keygen -b 2048 -t rsa -N '' -f #{key_path}").returns(true)
        
        deployer.deploy(nodes)
      end
      
      it 'should not overwrite files' do
        Engine.any_instance.stubs(:system).returns(true)
        
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
      
    end # end context
    
    context 'upload ssh keys' do
      before(:each) do
        deployer.stubs(:generate_ssh_key)
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

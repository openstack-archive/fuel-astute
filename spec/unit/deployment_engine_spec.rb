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
      
      deployer.expects(:generate_and_upload_ssh_keys).with(%w(nova mysql ceph), [1,2], 1)
      
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
  end

  describe '#generate_and_upload_ssh_keys' do
    #TODO: Add tests for generate_and_upload_ssh_keys
  end
end

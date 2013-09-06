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

describe "NailyFact DeploymentEngine" do
  include SpecHelpers
  
  context "When deploy is called, " do
    before(:each) do
      @ctx = mock
      @ctx.stubs(:task_id)
      @ctx.stubs(:deploy_log_parser).returns(Astute::LogParser::NoParsing.new)
      reporter = mock
      @ctx.stubs(:reporter).returns(reporter)
      reporter.stubs(:report)
      @deploy_engine = Astute::DeploymentEngine::NailyFact.new(@ctx)
    end
    
    let(:controller_nodes) do
      nodes_with_role(deploy_data, 'controller')
    end
    
    let(:compute_nodes) do 
      nodes_with_role(deploy_data, 'compute')
    end
    
    let(:cinder_nodes) do 
      nodes_with_role(deploy_data, 'cinder')
    end

    it "it should call valid method depends on attrs" do
      nodes = [{'uid' => 1, 'role' => 'controller'}]
      attrs = {'deployment_mode' => 'ha'}
      attrs_modified = attrs.merge({'some' => 'somea'})

      @deploy_engine.expects(:attrs_ha).with(nodes, attrs).returns(attrs_modified)
      @deploy_engine.expects(:deploy_ha).with(nodes, attrs_modified)
      # All implementations of deploy_piece go to subclasses
      @deploy_engine.respond_to?(:deploy_piece).should be_true
      
      external_nodes = [{'uid' => 1, 'roles' => ['controller']}]
      @deploy_engine.deploy(external_nodes, attrs)
    end

    it "it should raise an exception if deployment mode is unsupported" do
      nodes = [{'uid' => 1, 'roles' => ['controller']}]
      attrs = {'deployment_mode' => 'unknown'}
      expect {@deploy_engine.deploy(nodes, attrs)}.to raise_exception(/Method attrs_unknown is not implemented/)
    end

    context 'multinode deploy ' do
      let(:deploy_data) do
        Fixtures.common_attrs
      end

      it "should not raise any exception" do
        deploy_data['args']['attributes']['deployment_mode'] = "multinode"
        Astute::Metadata.expects(:publish_facts).times(deploy_data['args']['nodes'].size)
        # we got two calls, one for controller, and another for all computes
        Astute::PuppetdDeployer.expects(:deploy).with(@ctx, controller_nodes, instance_of(Fixnum), true).once
        Astute::PuppetdDeployer.expects(:deploy).with(@ctx, compute_nodes, instance_of(Fixnum), true).once
        @deploy_engine.deploy(deploy_data['args']['nodes'], deploy_data['args']['attributes'])
      end
    end
    
    context 'multiroles support' do
      let(:deploy_data) do
        data = Fixtures.multiroles_attrs
        data['args']['attributes']['deployment_mode'] = "multinode"
         # This role have same priority for multinode mode
        data['args']['nodes'][0]['roles'] = ['compute', 'cinder']
        data
      end
    
      let(:node_amount) { deploy_data['args']['nodes'][0]['roles'].size }
      
      it "multiroles for node should be support" do
        deploy_data['args']['nodes'][0]['roles'] = ['controller', 'compute'] 
        
        # we got two calls, one for controller, and another for all(1) computes
        Astute::Metadata.expects(:publish_facts).times(node_amount)
        Astute::PuppetdDeployer.expects(:deploy).with(@ctx, controller_nodes, instance_of(Fixnum), true).once
        Astute::PuppetdDeployer.expects(:deploy).with(@ctx, compute_nodes, instance_of(Fixnum), true).once
      
        @deploy_engine.deploy(deploy_data['args']['nodes'], deploy_data['args']['attributes'])
      end
    
      it "roles with the same priority for one node should deploy in series" do
        @ctx.stubs(:deploy_log_parser).returns(Astute::LogParser::ParseDeployLogs.new("multinode"))
      
        # we got two calls, one for compute, and another for cinder
        Astute::Metadata.expects(:publish_facts).times(node_amount)
        Astute::PuppetdDeployer.expects(:deploy).with(@ctx, compute_nodes, instance_of(Fixnum), true).once
        Astute::PuppetdDeployer.expects(:deploy).with(@ctx, cinder_nodes, instance_of(Fixnum), true).once
      
        @deploy_engine.deploy(deploy_data['args']['nodes'], deploy_data['args']['attributes'])
      end
    
      it "should prepare log parsing for every deploy call because node may be deployed several times" do
        Astute::Metadata.expects(:publish_facts).times(node_amount)
        @ctx.deploy_log_parser.expects(:prepare).with(compute_nodes).once
        @ctx.deploy_log_parser.expects(:prepare).with(cinder_nodes).once
      
        Astute::PuppetdDeployer.expects(:deploy).times(2)
       
        @deploy_engine.deploy(deploy_data['args']['nodes'], deploy_data['args']['attributes'])
      end
    
      it "should generate and publish facts for every deploy call because node may be deployed several times" do        
        @ctx.deploy_log_parser.expects(:prepare).with(compute_nodes).once
        @ctx.deploy_log_parser.expects(:prepare).with(cinder_nodes).once
        Astute::Metadata.expects(:publish_facts).times(node_amount)
      
        Astute::PuppetdDeployer.expects(:deploy).times(2)
       
        @deploy_engine.deploy(deploy_data['args']['nodes'], deploy_data['args']['attributes'])
      end
    end
    
    context 'ha deploy' do
      let(:deploy_data) do
        Fixtures.ha_attrs
      end

      it "ha deploy should not raise any exception" do
        Astute::Metadata.expects(:publish_facts).at_least_once
        
        primary_controller = controller_nodes.shift
        primary_controller['role'] = 'primary-controller'
        primary_controller.delete('roles')
        
        Astute::PuppetdDeployer.expects(:deploy).with(@ctx, [primary_controller], 2, true).once
        controller_nodes.each do |n|
          Astute::PuppetdDeployer.expects(:deploy).with(@ctx, [n], 2, true).once
        end
        Astute::PuppetdDeployer.expects(:deploy).with(@ctx, compute_nodes, instance_of(Fixnum), true).once
      
        @deploy_engine.deploy(deploy_data['args']['nodes'], deploy_data['args']['attributes'])
      end

      it "ha deploy should not raise any exception if there are only one controller" do
        Astute::Metadata.expects(:publish_facts).at_least_once
        Astute::PuppetdDeployer.expects(:deploy).once
        ctrl = deploy_data['args']['nodes'].find { |n| n['roles'].include? 'controller' }
        @deploy_engine.deploy([ctrl], deploy_data['args']['attributes'])
      end
    end

    describe 'Vlan manager' do
      it 'Should set fixed_interface value' do
        node = {
          'role' => 'controller',
          'uid' => 1,
          'vlan_interface' => 'eth2',
          'network_data' => [
            {
              "gateway" => "192.168.0.1",
              "name" => "management", "dev" => "eth0",
              "brd" => "192.168.0.255", "netmask" => "255.255.255.0",
              "vlan" => 102, "ip" => "192.168.0.2/24"
            }
          ],
          'meta' => {
            'interfaces' => [
              {
                'name' => 'eth1',
              }, {
                'name' => 'eth0',
              }
            ]
          }
        }
        attrs = {
          'novanetwork_parameters' => {
            'network_manager' => 'VlanManager'
          }
        }

        expect = {
          "role" => "controller",
          "uid" => 1,

          "network_data" => {"eth0.102" =>
            {
              "interface" => "eth0.102",
              "ipaddr" => ["192.168.0.2/24"]
            },
            "lo" => {
              "interface" => "lo",
              "ipaddr" => ["127.0.0.1/8"]
            },
            'eth1' => {
              'interface' => 'eth1',
              'ipaddr' => 'none'
            },
            'eth0' => {
              'interface' =>'eth0',
              'ipaddr' => 'none'
            },
          }.to_json,

          "fixed_interface" => "eth2",
          "novanetwork_parameters" => '{"network_manager":"VlanManager"}',
          "management_interface" => "eth0.102"
        }

        @deploy_engine.create_facts(node, attrs).should == expect
      end
    end
  end
end

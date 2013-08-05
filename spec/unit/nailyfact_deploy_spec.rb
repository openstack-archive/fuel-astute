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
  context "When deploy is called, " do
    before(:each) do
      @ctx = mock
      @ctx.stubs(:task_id)
      @ctx.stubs(:deploy_log_parser).returns(Astute::LogParser::NoParsing.new)
      reporter = mock
      @ctx.stubs(:reporter).returns(reporter)
      reporter.stubs(:report)
      @deploy_engine = Astute::DeploymentEngine::NailyFact.new(@ctx)
      meta = {
        'interfaces' => [
          {
            'name' => 'eth1',
          }, {
            'name' => 'eth0',
          }
        ]
      }
      @data = {"args" =>
                {"attributes" =>
                  {"storage_network_range" => "172.16.0.0/24", "auto_assign_floating_ip" => false,
                   "mysql" => {"root_password" => "Z2EqsZo5"},
                   "keystone" => {"admin_token" => "5qKy0i63", "db_password" => "HHQ86Rym", "admin_tenant" => "admin"},
                   "nova" => {"user_password" => "h8RY8SE7", "db_password" => "Xl9I51Cb"},
                   "glance" => {"user_password" => "nDlUxuJq", "db_password" => "V050pQAn"},
                   "rabbit" => {"user" => "nova", "password" => "FLF3txKC"},
                   "management_network_range" => "192.168.0.0/24",
                   "public_network_range" => "240.0.1.0/24",
                   "fixed_network_range" => "10.0.0.0/24",
                   "floating_network_range" => "240.0.0.0/24"},
               "task_uuid" => "19d99029-350a-4c9c-819c-1f294cf9e741",
               "nodes" => [{"mac" => "52:54:00:0E:B8:F5", "status" => "provisioning",
                            "uid" => "devnailgun.mirantis.com", "error_type" => nil,
                            "fqdn" => "devnailgun.mirantis.com",
                            "network_data" => [{"gateway" => "192.168.0.1",
                                                "name" => "management", "dev" => "eth0",
                                                "brd" => "192.168.0.255", "netmask" => "255.255.255.0",
                                                "vlan" => 102, "ip" => "192.168.0.2/24"},
                                               {"gateway" => "240.0.1.1",
                                                "name" => "public", "dev" => "eth0",
                                                "brd" => "240.0.1.255", "netmask" => "255.255.255.0",
                                                "vlan" => 101, "ip" => "240.0.1.2/24"},
                                               {"name" => "floating", "dev" => "eth0", "vlan" => 120},
                                               {"name" => "fixed", "dev" => "eth0", "vlan" => 103},
                                               {"name" => "storage", "dev" => "eth0", "vlan" => 104,
                                                "ip" => "172.16.1.2/24", "netmask" => "255.255.255.0",
                                                "brd" => "172.16.1.255"}],
                            "id" => 1,
                            "ip" => "10.20.0.200",
                            "role" => "controller",
                            'meta' => meta},
                           {"mac" => "52:54:00:50:91:DD", "status" => "provisioning",
                            "uid" => 2, "error_type" => nil,
                            "fqdn" => "slave-2.mirantis.com",
                            "network_data" => [{"gateway" => "192.168.0.1",
                                                "name" => "management", "dev" => "eth0",
                                                "brd" => "192.168.0.255", "netmask" => "255.255.255.0",
                                                "vlan" => 102, "ip" => "192.168.0.3/24"},
                                               {"gateway" => "240.0.1.1",
                                                "name" => "public", "dev" => "eth0",
                                                "brd" => "240.0.1.255", "netmask" => "255.255.255.0",
                                                "vlan" => 101, "ip" => "240.0.1.3/24"},
                                               {"name" => "floating", "dev" => "eth0", "vlan" => 120},
                                               {"name" => "fixed", "dev" => "eth0", "vlan" => 103},
                                               {"name" => "storage", "dev" => "eth0", "vlan" => 104,
                                                "ip" => "172.16.1.3/24", "netmask" => "255.255.255.0",
                                                "brd" => "172.16.1.255"}],
                            "id" => 2,
                            "ip" => "10.20.0.221",
                            "role" => "compute",
                            'meta' => meta},
                           {"mac" => "52:54:00:C3:2C:28", "status" => "provisioning",
                            "uid" => 3, "error_type" => nil,
                            "fqdn" => "slave-3.mirantis.com",
                            "network_data" => [{"gateway" => "192.168.0.1",
                                                "name" => "management", "dev" => "eth0",
                                                "brd" => "192.168.0.255", "netmask" => "255.255.255.0",
                                                "vlan" => 102, "ip" => "192.168.0.4/24"},
                                               {"gateway" => "240.0.1.1",
                                                "name" => "public", "dev" => "eth0",
                                                "brd" => "240.0.1.255", "netmask" => "255.255.255.0",
                                                "vlan" => 101, "ip" => "240.0.1.4/24"},
                                               {"name" => "floating", "dev" => "eth0", "vlan" => 120},
                                               {"name" => "fixed", "dev" => "eth0", "vlan" => 103},
                                               {"name" => "storage", "dev" => "eth0", "vlan" => 104,
                                                "ip" => "172.16.1.4/24", "netmask" => "255.255.255.0",
                                                "brd" => "172.16.1.255"}],
                            "id" => 3,
                            "ip" => "10.20.0.68",
                            "role" => "compute",
                            'meta' => meta}]},
              "method" => "deploy",
              "respond_to" => "deploy_resp"}

      @data['args']['attributes']['controller_nodes'] = @data['args']['nodes'].
        select { |node| node['role'] == 'controller'}

      ha_nodes = @data['args']['nodes'] +
                          [{"mac" => "52:54:00:0E:88:88", "status" => "provisioned",
                            "uid" => "4", "error_type" => nil,
                            "fqdn" => "controller-4.mirantis.com",
                            "network_data" => [{"gateway" => "192.168.0.1",
                                                "name" => "management", "dev" => "eth0",
                                                "brd" => "192.168.0.255", "netmask" => "255.255.255.0",
                                                "vlan" => 102, "ip" => "192.168.0.5/24"},
                                               {"gateway" => "240.0.1.1",
                                                "name" => "public", "dev" => "eth0",
                                                "brd" => "240.0.1.255", "netmask" => "255.255.255.0",
                                                "vlan" => 101, "ip" => "240.0.1.5/24"},
                                               {"name" => "floating", "dev" => "eth0", "vlan" => 120},
                                               {"name" => "fixed", "dev" => "eth0", "vlan" => 103},
                                               {"name" => "storage", "dev" => "eth0", "vlan" => 104,
                                                "ip" => "172.16.1.5/24", "netmask" => "255.255.255.0",
                                                "brd" => "172.16.1.255"}],
                            "id" => 4,
                            "ip" => "10.20.0.205",
                            "role" => "controller",
                            'meta' => meta},
                           {"mac" => "52:54:00:0E:99:99", "status" => "provisioned",
                            "uid" => "5", "error_type" => nil,
                            "fqdn" => "controller-5.mirantis.com",
                            "network_data" => [{"gateway" => "192.168.0.1",
                                                "name" => "management", "dev" => "eth0",
                                                "brd" => "192.168.0.255", "netmask" => "255.255.255.0",
                                                "vlan" => 102, "ip" => "192.168.0.6/24"},
                                               {"gateway" => "240.0.1.1",
                                                "name" => "public", "dev" => "eth0",
                                                "brd" => "240.0.1.255", "netmask" => "255.255.255.0",
                                                "vlan" => 101, "ip" => "240.0.1.6/24"},
                                               {"name" => "floating", "dev" => "eth0", "vlan" => 120},
                                               {"name" => "fixed", "dev" => "eth0", "vlan" => 103},
                                               {"name" => "storage", "dev" => "eth0", "vlan" => 104,
                                                "ip" => "172.16.1.6/24", "netmask" => "255.255.255.0",
                                                "brd" => "172.16.1.255"}],
                            "id" => 5,
                            "ip" => "10.20.0.206",
                            "role" => "controller",
                            'meta' => meta}]
      @data_ha = Marshal.load(Marshal.dump(@data))
      @data_ha['args']['nodes'] = ha_nodes
      @data_ha['args']['attributes']['deployment_mode'] = "ha"
      # VIPs are required for HA mode and should be passed from Nailgun (only in HA)
      @data_ha['args']['attributes']['management_vip'] = "192.168.0.111"
      @data_ha['args']['attributes']['public_vip'] = "240.0.1.111"
    end

    it "it should call valid method depends on attrs" do
      nodes = [{'uid' => 1}]
      attrs = {'deployment_mode' => 'ha'}
      attrs_modified = attrs.merge({'some' => 'somea'})

      @deploy_engine.expects(:attrs_ha).with(nodes, attrs).returns(attrs_modified)
      @deploy_engine.expects(:deploy_ha).with(nodes, attrs_modified)
      # All implementations of deploy_piece go to subclasses
      @deploy_engine.respond_to?(:deploy_piece).should be_true
      @deploy_engine.deploy(nodes, attrs)
    end

    it "it should raise an exception if deployment mode is unsupported" do
      nodes = [{'uid' => 1}]
      attrs = {'deployment_mode' => 'unknown'}
      expect {@deploy_engine.deploy(nodes, attrs)}.to raise_exception(/Method attrs_unknown is not implemented/)
    end

    it "multinode deploy should not raise any exception" do
      @data['args']['attributes']['deployment_mode'] = "multinode"
      Astute::Metadata.expects(:publish_facts).times(@data['args']['nodes'].size)
      # we got two calls, one for controller, and another for all computes
      controller_nodes = @data['args']['nodes'].select{|n| n['role'] == 'controller'}
      compute_nodes = @data['args']['nodes'].select{|n| n['role'] == 'compute'}
      Astute::PuppetdDeployer.expects(:deploy).with(@ctx, controller_nodes, instance_of(Fixnum), true).once
      Astute::PuppetdDeployer.expects(:deploy).with(@ctx, compute_nodes, instance_of(Fixnum), true).once
      @deploy_engine.deploy(@data['args']['nodes'], @data['args']['attributes'])
    end

    it "ha deploy should not raise any exception" do
      Astute::Metadata.expects(:publish_facts).at_least_once
      controller_nodes = @data_ha['args']['nodes'].select{|n| n['role'] == 'controller'}
      primary_nodes = [controller_nodes.shift]
      compute_nodes = @data_ha['args']['nodes'].select{|n| n['role'] == 'compute'}
      controller_nodes.each do |n|
        Astute::PuppetdDeployer.expects(:deploy).with(@ctx, [n], 2, true).once
      end
      Astute::PuppetdDeployer.expects(:deploy).with(@ctx, primary_nodes, 2, true).once
      Astute::PuppetdDeployer.expects(:deploy).with(@ctx, compute_nodes, instance_of(Fixnum), true).once
      @deploy_engine.deploy(@data_ha['args']['nodes'], @data_ha['args']['attributes'])
    end

    it "ha deploy should not raise any exception if there are only one controller" do
      Astute::Metadata.expects(:publish_facts).at_least_once
      Astute::PuppetdDeployer.expects(:deploy).once
      ctrl = @data_ha['args']['nodes'].select {|n| n['role'] == 'controller'}[0]
      @deploy_engine.deploy([ctrl], @data_ha['args']['attributes'])
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

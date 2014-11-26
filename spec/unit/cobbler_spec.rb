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

include Astute::Provision

describe Cobbler do
  include SpecHelpers

  it "should be able to be initialized with 'url'" do
    host = "host.domain.tld"
    port = "1234"
    path = "/api"
    username = 'user'
    password = 'pass'

    remote = mock()
    tmp = XMLRPC::Client
    XMLRPC::Client = mock() do
      expects(:new).with(host, path, port).returns(remote)
    end
    Astute::Provision::Cobbler.new(
                               'url' => "http://#{host}:#{port}#{path}",
                               'username' => username,
                               'password' => password
                               )
    XMLRPC::Client = tmp
  end

  it "should be able to be initialized with 'host', 'port', 'path'" do
    username = 'user'
    password = 'pass'
    host = "host.domain.tld"
    path = "/api"
    port = "1234"
    remote = mock()
    tmp = XMLRPC::Client
    XMLRPC::Client = mock() do
      expects(:new).with(host, path, port).returns(remote)
    end
    Astute::Provision::Cobbler.new(
                               'host' => host,
                               'port' => port,
                               'path' => path,
                               'username' => username,
                               'password' => password
                               )
    XMLRPC::Client = tmp
  end

  context "cobbler methods" do
    before(:each) do
      remote = mock() do
        stubs(:call)
        stubs(:call).with('login', 'cobbler', 'cobbler').returns('remotetoken')
      end
      @tmp = XMLRPC::Client
      XMLRPC::Client = mock() do
        stubs(:new).returns(remote)
      end
    end

    let(:data) do
      {
        'profile' => 'centos-x86_64',
        'power_type' => 'ssh',
        'power_user' => 'root',
        'power_pass' => '/root/.ssh/bootstrap.rsa',
        'power-address' => '1.2.3.5',
        'hostname' => 'name.domain.tld',
        'name_servers' => '1.2.3.4 1.2.3.100',
        'name_servers_search' => 'some.domain.tld domain.tld',
        'netboot_enabled' => '1',
        'ks_meta' => 'some_param=1 another_param=2',
        'interfaces' => {
          'eth0' => {
            'mac_address' => '00:00:00:00:00:00',
            'static' => '1',
            'netmask' => '255.255.255.0',
            'ip_address' => '1.2.3.5',
            'dns_name' => 'node.mirantis.net',
          },
          'eth1' => {
            'mac_address' => '00:00:00:00:00:01',
            'static' => '0',
            'netmask' => '255.255.255.0',
            'ip_address' => '1.2.3.6',
          }
        },
        'interfaces_extra' => {
          'eth0' => {
            'peerdns' => 'no',
            'onboot' => 'yes',
          },
          'eth1' => {
            'peerdns' => 'no',
            'onboot' => 'yes',
          }
        }
      }
    end

    after(:each) do
      XMLRPC::Client = @tmp
    end

    it "item_from_hash should remove item if 'item_preremove' is true" do
      Astute::Provision::Cobbler.any_instance do
        expects(:remove_item).with('system', 'name')
      end
      cobbler = Astute::Provision::Cobbler.new
      cobbler.item_from_hash('system', 'name', {}, :item_preremove => true)
    end

    it "item_from_hash should create new item if it does not exist" do
      cobbler = Astute::Provision::Cobbler.new
      cobbler.remote.expects(:call).with('has_item', 'system', 'name').returns(false)
      cobbler.remote.expects(:call).with('new_item', 'system', cobbler.token).returns('itemid')
      cobbler.remote.expects(:call).with('modify_item', 'system', 'itemid', 'name', 'name', cobbler.token)
      cobbler.item_from_hash('system', 'name', {}, :item_preremove => true)
    end

    it "item_from_hash should modify existent item if it does exist" do
      cobbler = Astute::Provision::Cobbler.new
      cobbler.remote.expects(:call).with('has_item', 'system', 'name').returns(true)
      cobbler.remote.expects(:call).with('get_item_handle', 'system', 'name', cobbler.token).returns('itemid')
      cobbler.item_from_hash('system', 'name', {}, :item_preremove => false)
    end

    it "item_from_hash should modify item with cobblerized data" do
      cobblerized_data = Astute::Provision::Cobsh.new(data.merge({'what' => 'system', 'name' => 'name'})).cobblerized
      cobbler = Astute::Provision::Cobbler.new
      cobbler.stubs(:get_item_id).with('system', 'name').returns('itemid')
      cobblerized_data.each do |opt, value|
        next if opt == 'interfaces'
        cobbler.remote.expects(:call).with(
                                      'modify_item',
                                      'system',
                                      'itemid',
                                      opt,
                                      value,
                                      'remotetoken'
                                      )
      end
      cobbler.item_from_hash('system', 'name', data, :item_preremove => true)
    end

    it "item_from_hash should modify 'system' interfaces with cobblerized['interfaces']" do
      cobblerized_data = Astute::Provision::Cobsh.new(data.merge({'what' => 'system', 'name' => 'name'})).cobblerized
      cobbler = Astute::Provision::Cobbler.new
      cobbler.stubs(:get_item_id).with('system', 'name').returns('itemid')
      cobbler.remote.expects(:call).with(
                                    'modify_system',
                                    'itemid',
                                    'modify_interface',
                                    cobblerized_data['interfaces'],
                                    'remotetoken')
      cobbler.item_from_hash('system', 'name', data, :item_preremove => true)
    end

    it 'should generate token in every cobbler call where token need' do
      remote = mock() do
        stubs(:call).twice.with('sync', 'remotetoken')
        expects(:call).twice.with('login', 'cobbler', 'cobbler').returns('remotetoken')
      end
      XMLRPC::Client = mock() do
        stubs(:new).returns(remote)
      end
      cobbler = Astute::Provision::Cobbler.new
      cobbler.sync
      cobbler.sync
    end

    it 'should try sync several time before raise a exception (Net)' do
      remote = mock() do
        stubs(:call).with('sync', 'remotetoken')
          .raises(Net::ReadTimeout)
          .then.returns(nil)
        stubs(:call).twice.with('login', 'cobbler', 'cobbler').returns('remotetoken')
      end
      XMLRPC::Client = mock() do
        stubs(:new).returns(remote)
      end
      cobbler = Astute::Provision::Cobbler.new
      cobbler.stubs(:sleep).with(10).times(1)

      expect { cobbler.sync }.to_not raise_exception(Net::ReadTimeout)
    end

    it 'should try sync several time before raise a exception (XMLRPC)' do
      remote = mock() do
        stubs(:call).with('sync', 'remotetoken')
          .raises(XMLRPC::FaultException.new("", ""))
          .then.returns(nil)
        stubs(:call).twice.with('login', 'cobbler', 'cobbler').returns('remotetoken')
      end
      XMLRPC::Client = mock() do
        stubs(:new).returns(remote)
      end
      cobbler = Astute::Provision::Cobbler.new
      cobbler.stubs(:sleep).with(10).times(1)

      expect { cobbler.sync }.to_not raise_exception(XMLRPC::FaultException)
    end

    it 'should raise a exception if sync do not succeed after several(3) tries' do
      remote = mock() do
        stubs(:call).with('sync', 'remotetoken')
          .raises(Net::ReadTimeout)
          .then.raises(Net::ReadTimeout)
          .then.raises(Net::ReadTimeout)
        stubs(:call).times(3).with('login', 'cobbler', 'cobbler').returns('remotetoken')
      end
      XMLRPC::Client = mock() do
        stubs(:new).returns(remote)
      end
      cobbler = Astute::Provision::Cobbler.new
      cobbler.stubs(:sleep).with(10).times(2)

      expect { cobbler.sync }.to raise_exception(Net::ReadTimeout)
    end

  end
end



describe Cobsh do
  before(:each) do

    @aliases = {
      'ks_meta' => ['ksmeta'],
      'mac_address' => ['mac'],
      'ip_address' => ['ip'],
    }

    @fields = {
      'system' => {
        'fields' => [
          'name', 'owners', 'profile', 'image', 'status', 'kernel_options',
          'kernel_options_post', 'ks_meta', 'enable_gpxe', 'proxy',
          'netboot_enabled', 'kickstart', 'comment', 'server',
          'virt_path', 'virt_type', 'virt_cpus', 'virt_file_size',
          'virt_disk_driver', 'virt_ram', 'virt_auto_boot', 'power_type',
          'power_address', 'power_user', 'power_pass', 'power_id',
          'hostname', 'gateway', 'name_servers', 'name_servers_search',
          'ipv6_default_device', 'ipv6_autoconfiguration', 'mgmt_classes',
          'mgmt_parameters', 'boot_files', 'fetchable_files',
          'template_files', 'redhat_management_key', 'redhat_management_server',
          'repos_enabled', 'ldap_enabled', 'ldap_type', 'monit_enabled',
        ],
        'interfaces_fields' => [
          'mac_address', 'mtu', 'ip_address', 'interface_type',
          'interface_master', 'bonding_opts', 'bridge_opts',
          'management', 'static', 'netmask', 'dhcp_tag', 'dns_name',
          'static_routes', 'virt_bridge', 'ipv6_address', 'ipv6_secondaries',
          'ipv6_mtu', 'ipv6_static_routes', 'ipv6_default_gateway'
        ],
        'special' => ['interfaces', 'interfaces_extra']
      },
      'profile' => {
        'fields' => [
          'name', 'owners', 'distro', 'parent', 'enable_gpxe',
          'enable_menu', 'kickstart', 'kernel_options', 'kernel_options_post',
          'ks_meta', 'proxy', 'repos', 'comment', 'virt_auto_boot',
          'virt_cpus', 'virt_file_size', 'virt_disk_driver',
          'virt_ram', 'virt_type', 'virt_path', 'virt_bridge',
          'dhcp_tag', 'server', 'name_servers', 'name_servers_search',
          'mgmt_classes', 'mgmt_parameters', 'boot_files', 'fetchable_files',
          'template_files', 'redhat_management_key', 'redhat_management_server'
        ]
      },
      'distro' => {
        'fields' => ['name', 'owners', 'kernel', 'initrd', 'kernel_options',
          'kernel_options_post', 'ks_meta', 'arch', 'breed',
          'os_version', 'comment', 'mgmt_classes', 'boot_files',
          'fetchable_files', 'template_files', 'redhat_management_key',
          'redhat_management_server']
      }
    }

    @minimal_data = {
      'what' => 'system',
      'name' => 'name',
    }

  end

  it "should raise exception when init data do not contain 'what'" do
    expect {
      Astute::Provision::Cobsh.new({'what'=>'system'})
    }.to raise_exception(/Cobbler hash must have 'name' key/)
  end

  it "should raise exception when init data do not contain 'name'" do
    expect {
      Astute::Provision::Cobsh.new({'name'=>'name'})
    }.to raise_exception(/Cobbler hash must have 'what' key/)
  end

  it "should raise exception when init data 'what' is not supported" do
    expect {
      Astute::Provision::Cobsh.new({
                                     'what' => 'unsupported',
                                     'name'=>'name'
                                   })
    }.to raise_exception(/Unsupported 'what' value/)
  end

  it "should replace '-' into '_' in init data keys" do
    data = @minimal_data.merge({'power_id' => 'blabla'})
    expected = {
      'name' => data['name'],
      'power_id' => 'blabla'
    }
    Astute::Provision::Cobsh.new(data).cobblerized.should eql(expected)
  end

  it "returns cobblerizied data with aliased keys" do
    @fields.each do |what, what_data|
      @aliases.each do |main_alias, alias_list|
        data = {'name' => 'name'}
        expected = {'name' => 'name'}
        if what_data['fields'].include? main_alias
          data['what'] = what
          alias_list.each do |a|
            data2 = data.merge({a => 'blabla'})
            expected2 = expected.merge({main_alias => 'blabla'})
            Astute::Provision::Cobsh.new(data2).cobblerized.should eql(expected2)
          end
        elsif what_data.has_key? 'interfaces_fields' and what_data['interfaces_fields'].include? main_alias
          data['what'] = what
          alias_list.each do |a|
            data2 = data.merge({
                                 'interfaces' => {
                                   'eth0' => {a => 'blabla'}
                                 }
                               })
            expected2 = expected.merge({
                                         'interfaces' => {
                                           "#{main_alias}-eth0" => 'blabla'
                                         }
                                       })
            Astute::Provision::Cobsh.new(data2).cobblerized.should eql(expected2)
          end
        end
      end
    end
  end

  it "should raise exception when keys are duplicated in init data" do
    data = @minimal_data.merge({'ks-meta' => 'ks-meta', 'ksmeta' => 'ksmeta'})
    expect {
      Astute::Provision::Cobsh.new(data).cobblerized
    }.to raise_exception(/Wrong cobbler data: .* is duplicated/)
  end

  it "should cut out 'system' unsupported keys" do
    data = {'what' => 'system'}
    expected = {}
    @fields['system']['fields'].each do |f|
      data[f] = f
      expected[f] = f
    end
    @fields['system']['interfaces_fields'].each do |f|
      data['interfaces'] = {'eth0' => {}} unless data.has_key? 'interfaces'
      data['interfaces']['eth0'][f] = f
      expected['interfaces'] = {} unless expected.has_key? 'interfaces'
      expected['interfaces']["#{f}-eth0"] = f
    end
    data['unsupported'] = 'unsupported'
    Astute::Provision::Cobsh.new(data).cobblerized.should eql(expected)
  end

  it "should cut out 'profile' unsupported keys" do
    data = {'what' => 'profile'}
    expected = {}
    @fields['profile']['fields'].each do |f|
      data[f] = f
      expected[f] = f
    end
    data['unsupported'] = 'unsupported'
    Astute::Provision::Cobsh.new(data).cobblerized.should eql(expected)
  end

  it "should cut out 'distro' unsupported keys" do
    data = {'what' => 'distro'}
    expected = {}
    @fields['distro']['fields'].each do |f|
      data[f] = f
      expected[f] = f
    end
    data['unsupported'] = 'unsupported'
    Astute::Provision::Cobsh.new(data).cobblerized.should eql(expected)
  end

  it "should append extra interfaces data into ks_meta" do
    RSpec::Matchers.define :ks_meta_equal? do |ks_meta|
      match do |ks_meta_self|
        equal = true
        ks_meta_self.strip.split.each do |i|
          equal = false unless ks_meta =~ /.*?#{i}.*?/
        end
        ks_meta.strip.split.each do |i|
          equal = false unless ks_meta_self =~ /.*?#{i}.*?/
        end
        equal
      end
    end

    data = @minimal_data.merge({
                                 'interfaces_extra' => {
                                   'eth0' => {
                                     'blabla' => 'blabla',
                                     'blabla2' => 'blabla2',
                                   }
                                 }
                               })
    expected_ks_meta = "interface_extra_eth0_blabla=blabla interface_extra_eth0_blabla2=blabla2"
    Astute::Provision::Cobsh.new(data).cobblerized['ks_meta'].should ks_meta_equal?(expected_ks_meta)
  end

end



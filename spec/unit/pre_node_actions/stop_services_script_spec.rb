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

#require File.join(File.dirname(__FILE__), '../../spec_helper')

RSpec.configure do |c|
  c.mock_with :mocha
end

load File.join(File.dirname(__FILE__), '../../../lib/astute/pre_node_actions/stop_services.script')

describe PreDeploy do
#  include SpecHelpers

  let(:redhat_ps) do
    <<-eos
100 1 /usr/bin/python nova-api.py
101 100 /usr/bin/python nova-api.py
102 100 /usr/bin/python nova-api.py
103 100 /usr/bin/python nova-api.py
104 1 /usr/bin/python cinder-volume.py
105 104 /usr/sbin/tgtd
106 1 /usr/bin/python neutron.py
107 106 /usr/sbin/dnsmasq
108 1 /usr/sbin/httpd
109 1 /usr/bin/python keystone.py
    eos
  end

  let(:debian_pstree) do
    {
        104 => {
            :children => [105],
            :ppid => 1,
            :cmd => "/usr/bin/python cinder-volume.py",
            :pid => 104
        },
        105 => {
            :children => [],
            :ppid => 104,
            :cmd => "/usr/sbin/tgtd",
            :pid => 105
        },
        100 => {
            :children => [101, 102, 103],
            :ppid => 1,
            :cmd => "/usr/bin/python nova-api.py",
            :pid => 100
        },
        1 => {
            :children => [100, 104, 106, 108, 109]
        },
        106 => {
            :children => [107],
            :ppid => 1,
            :cmd => "/usr/bin/python neutron.py",
            :pid => 106
        },
        101 => {
            :children => [],
            :ppid => 100,
            :cmd => "/usr/bin/python nova-api.py",
            :pid => 101
        },
        107 => {
            :children => [],
            :ppid => 106,
            :cmd => "/usr/sbin/dnsmasq",
            :pid => 107
        },
        102 => {
            :children => [],
            :ppid => 100,
            :cmd => "/usr/bin/python nova-api.py",
            :pid => 102
        },
        108 => {
            :children => [],
            :ppid => 1,
            :cmd => "/usr/sbin/apache2",
            :pid => 108
        },
        103 => {
            :children => [],
            :ppid => 100,
            :cmd => "/usr/bin/python nova-api.py",
            :pid => 103
        },
        109 => {
            :children => [],
            :ppid => 1,
            :cmd => "/usr/bin/python keystone.py",
            :pid => 109
        }
    }
  end

  let(:redhat_pstree) do
    {
        104 => {
            :children => [105],
            :ppid => 1,
            :cmd => "/usr/bin/python cinder-volume.py",
            :pid => 104
        },
        105 => {
            :children => [],
            :ppid => 104,
            :cmd => "/usr/sbin/tgtd",
            :pid => 105
        },
        100 => {
            :children => [101, 102, 103],
            :ppid => 1,
            :cmd => "/usr/bin/python nova-api.py",
            :pid => 100
        },
        1 => {
            :children => [100, 104, 106, 108, 109]
        },
        106 => {
            :children => [107],
            :ppid => 1,
            :cmd => "/usr/bin/python neutron.py",
            :pid => 106
        },
        101 => {
            :children => [],
            :ppid => 100,
            :cmd => "/usr/bin/python nova-api.py",
            :pid => 101
        },
        107 => {
            :children => [],
            :ppid => 106,
            :cmd => "/usr/sbin/dnsmasq",
            :pid => 107
        },
        102 => {
            :children => [],
            :ppid => 100,
            :cmd => "/usr/bin/python nova-api.py",
            :pid => 102
        },
        108 => {
            :children => [],
            :ppid => 1,
            :cmd => "/usr/sbin/httpd",
            :pid => 108
        },
        103 => {
            :children => [],
            :ppid => 100,
            :cmd => "/usr/bin/python nova-api.py",
            :pid => 103
        },
        109 => {
            :children => [],
            :ppid => 1,
            :cmd => "/usr/bin/python keystone.py",
            :pid => 109
        }
    }
  end

  let(:debian_ps) do
    <<-eos
100 1 /usr/bin/python nova-api.py
101 100 /usr/bin/python nova-api.py
102 100 /usr/bin/python nova-api.py
103 100 /usr/bin/python nova-api.py
104 1 /usr/bin/python cinder-volume.py
105 104 /usr/sbin/tgtd
106 1 /usr/bin/python neutron.py
107 106 /usr/sbin/dnsmasq
108 1 /usr/sbin/apache2
109 1 /usr/bin/python keystone.py
    eos
  end

  let(:debian_services) do
    <<-eos
 [ ? ]  ntpd
 [ ? ]  neutron
 [ + ]  cinder-volume
 [ - ]  nginx
 [ - ]  smbd
 [ + ]  sshd
 [ + ]  nova-api
 [ + ]  apache2
 [ + ]  keystone
    eos
  end

  let(:redhat_services) do
    <<-eos
ntpd is stopped
neutron is stopped
sshd (pid  50) is running...
cinder-volume (pid  104) is running...
nova-api (pid  100) is running...
nginx is stopped
smbd is stopped
httpd.event (pid  108) is running...
keystone (pid  109) is running...
    eos
  end

  let(:debian_services_to_stop) do
    ["cinder-volume", "nova-api", "apache2", "keystone"]
  end

  let(:redhat_services_to_stop) do
    ["cinder-volume", "nova-api", "httpd", "openstack-keystone"]
  end
###################################################################

  it 'should correctly parse ps output on Debian system' do
    subject.stubs(:ps).returns(debian_ps)
    subject.stubs(:osfamily).returns 'Debian'
    subject.process_tree_with_renew
    expect(subject.process_tree).to eq debian_pstree
  end

  it 'should correctly parse ps output on RedHat system' do
    subject.stubs(:ps).returns(redhat_ps)
    subject.stubs(:osfamily).returns 'RedHat'
    subject.process_tree_with_renew
    expect(subject.process_tree).to eq redhat_pstree
  end

  it 'should find services to stop on Debian system' do
    subject.stubs(:services).returns debian_services
    subject.stubs(:osfamily).returns 'Debian'
    subject.services_to_stop_with_renew
    expect(subject.services_to_stop).to eq debian_services_to_stop
  end

  it 'should find services to stop on RedHat system' do
    subject.stubs(:services).returns redhat_services
    subject.stubs(:osfamily).returns 'RedHat'
    subject.services_to_stop_with_renew
    expect(subject.services_to_stop).to eq redhat_services_to_stop
  end

  it 'should find processes by regexp' do
    subject.stubs(:ps).returns(debian_ps)
    subject.stubs(:osfamily).returns 'Debian'
    subject.process_tree_with_renew
    dnsmasq = {107 => {
        :children => [],
        :ppid => 106,
        :cmd => "/usr/sbin/dnsmasq",
        :pid => 107
    }}
    expect(subject.pids_by_regexp /dnsmasq/).to eq dnsmasq
  end

  it 'should kill correct processes on Debian system' do
    subject.stubs(:ps).returns(debian_ps)
    subject.stubs(:osfamily).returns 'Debian'
    subject.stubs(:dry_run).returns true
    subject.expects(:run).with 'kill -9 100 101 102 103 104 105 106 107 108 109'
    subject.process_tree_with_renew
    subject.kill_pids_by_stop_regexp
  end

  it 'should kill correct processes on RedHat system' do
    subject.stubs(:ps).returns(redhat_ps)
    subject.stubs(:osfamily).returns 'RedHat'
    subject.stubs(:dry_run).returns true
    subject.expects(:run).with 'kill -9 100 101 102 103 104 105 106 107 108 109'
    subject.process_tree_with_renew
    subject.kill_pids_by_stop_regexp
  end

  it 'should stop correct services on Debian system' do
    subject.stubs(:services).returns debian_services
    subject.stubs(:osfamily).returns 'Debian'
    subject.stubs(:dry_run).returns true
    subject.expects(:run).with 'service cinder-volume stop'
    subject.expects(:run).with 'service nova-api stop'
    subject.expects(:run).with 'service apache2 stop'
    subject.expects(:run).with 'service keystone stop'
    subject.services_to_stop_with_renew
    subject.stop_services
  end

  it 'should stop correct services on RedHat system' do
    subject.stubs(:services).returns redhat_services
    subject.stubs(:osfamily).returns 'RedHat'
    subject.stubs(:dry_run).returns true
    subject.expects(:run).with 'service cinder-volume stop'
    subject.expects(:run).with 'service nova-api stop'
    subject.expects(:run).with 'service httpd stop'
    subject.expects(:run).with 'service openstack-keystone stop'
    subject.services_to_stop_with_renew
    subject.stop_services
  end
end
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


module Fixtures

  def self.common_nodes
    [
      {
        "mac" => "52:54:00:0E:B8:F5",
        "status" => "provisioning",
        "uid" => "1",
        "error_type" => nil,
        "fqdn" => "controller-1.mirantis.com",
        "role" => "controller",
        "priority" => 10,
        "network_data" => [
          {
            "gateway" => "192.168.0.1",
            "name" => "management",
            "dev" => "eth0",
            "brd" => "192.168.0.255",
            "netmask" => "255.255.255.0",
            "vlan" => 102,
            "ip" => "192.168.0.2/24"
          }, {
            "gateway" => "240.0.1.1",
            "name" => "public",
            "dev" => "eth0",
            "brd" => "240.0.1.255",
            "netmask" => "255.255.255.0",
            "vlan" => 101,
            "ip" => "240.0.1.2/24"
          }, {
            "name" => "floating",
            "dev" => "eth0",
            "vlan" => 120
          }, {
            "name" => "fixed",
            "dev" => "eth0",
            "vlan" => 103
          }, {
            "name" => "storage",
            "dev" => "eth0",
            "vlan" => 104,
            "ip" => "172.16.1.2/24",
            "netmask" => "255.255.255.0",
            "brd" => "172.16.1.255"
          }
        ],
        "id" => 1,
        "ip" => "10.20.0.200",
        'meta' => meta
      }, {
        "mac" => "52:54:00:50:91:DD",
        "status" => "provisioning",
        "uid" => 2,
        "error_type" => nil,
        "fqdn" => "compute-2.mirantis.com",
        "role" => "compute",
        "priority" => 100,
        "network_data" => [
          {
            "gateway" => "192.168.0.1",
            "name" => "management",
            "dev" => "eth0",
            "brd" => "192.168.0.255",
            "netmask" => "255.255.255.0",
            "vlan" => 102,
            "ip" => "192.168.0.3/24"
          },
          {
            "gateway" => "240.0.1.1",
            "name" => "public",
            "dev" => "eth0",
            "brd" => "240.0.1.255",
            "netmask" => "255.255.255.0",
            "vlan" => 101,
            "ip" => "240.0.1.3/24"
          },
          {
            "name" => "floating",
            "dev" => "eth0",
            "vlan" => 120
          },
          {
            "name" => "fixed",
            "dev" => "eth0",
            "vlan" => 103
          },
          {
            "name" => "storage",
            "dev" => "eth0",
            "vlan" => 104,
            "ip" => "172.16.1.3/24",
            "netmask" => "255.255.255.0",
            "brd" => "172.16.1.255"
          }
        ],
        "id" => 2,
        "ip" => "10.20.0.221",
        'meta' => meta
      }, {
        "mac" => "52:54:00:C3:2C:28",
        "status" => "provisioning",
        "uid" => 3,
        "error_type" => nil,
        "fqdn" => "compute-3.mirantis.com",
        "role" => "compute",
        "priority" => 100,
        "network_data" => [
          {
            "gateway" => "192.168.0.1",
            "name" => "management",
            "dev" => "eth0",
            "brd" => "192.168.0.255",
            "netmask" => "255.255.255.0",
            "vlan" => 102,
            "ip" => "192.168.0.4/24"
          },
          {
            "gateway" => "240.0.1.1",
            "name" => "public",
            "dev" => "eth0",
            "brd" => "240.0.1.255",
            "netmask" => "255.255.255.0",
            "vlan" => 101,
            "ip" => "240.0.1.4/24"
          },
          {
            "name" => "floating",
            "dev" => "eth0",
            "vlan" => 120
          },
          {
            "name" => "fixed",
            "dev" => "eth0",
            "vlan" => 103
          },
          {
            "name" => "storage",
            "dev" => "eth0",
            "vlan" => 104,
            "ip" => "172.16.1.4/24",
            "netmask" => "255.255.255.0",
            "brd" => "172.16.1.255"
          }
        ],
        "id" => 3,
        "ip" => "10.20.0.68",
        'meta' => meta
      }
    ]
  end

  def self.meta
    {
      'interfaces' => [
        {
          'name' => 'eth1',
        }, {
          'name' => 'eth0',
        }
      ]
    }
  end

end

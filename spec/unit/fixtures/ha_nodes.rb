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

  def self.ha_nodes
    common_nodes + [
      {
        "mac" => "52:54:00:0E:88:88",
        "status" => "provisioned",
        "uid" => "4",
        "error_type" => nil,
        "fqdn" => "controller-4.mirantis.com",
        "role" => "primary-controller",
        "priority" => 0,
        "network_data" => [
          {
            "gateway" => "192.168.0.1",
            "name" => "management",
            "dev" => "eth0",
            "brd" => "192.168.0.255",
            "netmask" => "255.255.255.0",
            "vlan" => 102,
            "ip" => "192.168.0.5/24"
          },
          {
            "gateway" => "240.0.1.1",
            "name" => "public",
            "dev" => "eth0",
            "brd" => "240.0.1.255",
            "netmask" => "255.255.255.0",
            "vlan" => 101,
            "ip" => "240.0.1.5/24"
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
            "ip" => "172.16.1.5/24",
            "netmask" => "255.255.255.0",
            "brd" => "172.16.1.255"
          }
        ],
        "id" => 4,
        "ip" => "10.20.0.205",
        'meta' => meta
      },
      {
        "mac" => "52:54:00:0E:99:99",
        "status" => "provisioned",
        "uid" => "5",
        "error_type" => nil,
        "fqdn" => "controller-5.mirantis.com",
        "role" => "controller",
        "priority" => 50,
        "network_data" => [
          {
            "gateway" => "192.168.0.1",
            "name" => "management",
            "dev" => "eth0",
            "brd" => "192.168.0.255",
            "netmask" => "255.255.255.0",
            "vlan" => 102,
            "ip" => "192.168.0.6/24"
          },
          {
            "gateway" => "240.0.1.1",
            "name" => "public",
            "dev" => "eth0",
            "brd" => "240.0.1.255",
            "netmask" => "255.255.255.0",
            "vlan" => 101,
            "ip" => "240.0.1.6/24"
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
            "ip" => "172.16.1.6/24",
            "netmask" => "255.255.255.0",
            "brd" => "172.16.1.255"
          }
        ],
        "id" => 5,
        "ip" => "10.20.0.206",
        'meta' => meta
      }
    ]
  end

end

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

  def self.common_attrs(deployment_mode, nodes)
    nodes.each do |node|
      node.merge(
        "deployment_id" => 1,
        "storage_network_range" => "172.16.0.0/24",
        "auto_assign_floating_ip" => false,
        "mysql" => {
          "root_password" => "Z2EqsZo5"
        },
        "keystone" => {
          "admin_token" => "5qKy0i63",
          "db_password" => "HHQ86Rym",
          "admin_tenant" => "admin"
        },
        "nova" => {
          "user_password" => "h8RY8SE7",
          "db_password" => "Xl9I51Cb"
        },
        "glance" => {
          "user_password" => "nDlUxuJq",
          "db_password" => "V050pQAn"
        },
        "rabbit" => {
          "user" => "nova",
          "password" => "FLF3txKC"
        },
        "management_network_range" => "192.168.0.0/24",
        "public_network_range" => "240.0.1.0/24",
        "fixed_network_range" => "10.0.0.0/24",
        "floating_network_range" => "240.0.0.0/24",
        "task_uuid" => "19d99029-350a-4c9c-819c-1f294cf9e741",
        "deployment_mode" => deployment_mode,
        "controller_nodes" => controller_nodes(nodes)
      )
    end
  end
  
  def self.controller_nodes(nodes)
    controller_nodes = nodes.select{ |n| n['role'] == 'controller' }.map { |e| deep_copy e }
  end
end

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

  def self.ha_attrs
    attrs = common_attrs

    attrs['args']['nodes'] = ha_nodes
    
    attrs['args']['attributes']['deployment_mode'] = "ha"
    attrs['args']['attributes']['management_vip'] = "192.168.0.111"
    attrs['args']['attributes']['public_vip'] = "240.0.1.111"
    attrs['args']["controller_nodes"] = controller_nodes(attrs['args']['nodes'])

    attrs
  end

end

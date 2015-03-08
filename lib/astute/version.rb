#    Copyright 2015 Mirantis, Inc.
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


module Astute
  VERSION = '6.1.0'
  class Versioning
    def initialize(context)
      @ctx = context
    end

    def get_versions(nodes_uids, timeout=nil)
      result = {}
      rpcutil = MClient.new(@ctx, "rpcutil", nodes_uids, check_result=true, timeout)
      inventory = rpcutil.inventory
      inventory.each |node| do
        if node.results[:data][:agents].include? 'version'
          with_version.push(node.results[:sender])
        end
      end
      no_version = nodes_uids - with_version
      version = MClient.new(@ctx, "version", with_version, check_result=true, timeout)
      versions = version.get_versions
      versions.each |node| do
        uid = node.results[:sender]
        result << {'version' => node.results[:data][:version],
                   'uid' => uid}
      end

      # times before versioning
      no_version.each |uid| do
        result << {'version' => 6.0.0,
                   'uid' => uid}
      end
      result
    end

    def split_on_version(reporter, task_id, nodes_uids, version, timeout=nil)
      versions = get_versions(reporter, task_id, nodes_uids, timeout)
      version = Gem::Version.new(version)
      smaller = versions.select{ |n|  Gem::Version.new() < version }
      eq_and_bigger = versions.select{ |n|  Gem::Version.new() >= version }
      [smaller, eq_and_bigger]
    end
end

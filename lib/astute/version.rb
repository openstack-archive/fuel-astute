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


module Astute
  VERSION = '10.0.0'
  class Versioning
    def initialize(context)
      @ctx = context
    end

    def get_versions(nodes_uids, timeout=nil)
      result = []
      with_version = []
      rpcutil = MClient.new(@ctx, "rpcutil", nodes_uids, check_result=true, timeout)
      inventory = rpcutil.inventory
      inventory.each do |node|
        if node.results[:data][:agents].include? 'version'
          with_version.push(node.results[:sender])
        end
      end
      no_version = nodes_uids - with_version
      if with_version.present?
        version = MClient.new(@ctx, "version", with_version, check_result=true, timeout)
        versions = version.get_version
        versions.each do |node|
          uid = node.results[:sender]
          result << {'version' => node.results[:data][:version],
                     'uid' => uid}
        end
      end

      # times before versioning
      no_version.each do |uid|
        result << {'version' => '6.0.0',
                   'uid' => uid}
      end
      result
    end

    def split_on_version(nodes_uids, version, timeout=nil)
      versions = get_versions(nodes_uids, timeout)
      version = Gem::Version.new(version)
      smaller = versions.select{ |n|  Gem::Version.new(n["version"]) < version }
      eq_and_bigger = versions.select{ |n|  Gem::Version.new(n["version"]) >= version }
      [smaller, eq_and_bigger]
    end
  end
end

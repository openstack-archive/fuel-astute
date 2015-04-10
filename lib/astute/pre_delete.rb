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
  module PreDelete

    def self.check_ceph_osds(ctx, nodes)
      answer = {"status" => "ready"}
      ceph_nodes = nodes.select { |n| n["roles"].include? "ceph-osd" }
      ceph_osds = ceph_nodes.collect{ |n| n["slave_name"] }
      return answer if ceph_osds.empty?

      cmd = "ceph -f json osd tree"
      shell = MClient.new(ctx, "execute_shell_command", [ceph_nodes[0]["id"]], timeout=60, retries=1)
      result = shell.execute(:cmd => cmd).first.results

      osds = {}
      tree = JSON.parse(result[:data][:stdout])

      tree["nodes"].each do |osd|
        osds[osd["name"]] = osd["children"] if ceph_osds.include? osd["name"]
      end

      # pg dump lists all pgs in the cluster and where they are located.
      # $14 is the 'up set' (the list of OSDs responsible for a particular
      # pg for an epoch) and $16 is the 'acting set' (list of OSDs who
      # are [or were at some point] responsible for a pg). These sets
      # will generally be the same.
      osd_list = osds.values.flatten.join("|")
      cmd = "ceph pg dump 2>/dev/null | " \
            "awk '//{print $14, $16}' | " \
            "egrep -o '\\<(#{osd_list})\\>' | " \
            "sort -un"

      result = shell.execute(:cmd => cmd).first.results
      rs = result[:data][:stdout].split("\n")

      # JSON.parse returns the children as integers, so the result from the
      # shell command needs to be converted for the set operations to work.
      rs.map! { |x| x.to_i }

      error_nodes = []
      osds.each do |name, children|
        error_nodes << name if rs & children != []
      end

      if not error_nodes.empty?
        msg = "Ceph data still exists on: #{error_nodes.join(', ')}. " \
              "You must manually remove the OSDs from the cluster " \
              "and allow Ceph to rebalance before deleting these nodes."
        answer = {"status" => "error", "error" => msg}
      end

      answer
    end

    def self.check_ceph_mons(ctx, nodes)
      answer = {"status" => "ready"}
      ceph_nodes = nodes.select { |n| n["roles"].include? "controller" }

      ceph_nodes.each do | node |
        cmd = "ceph-conf --lookup mon_initial_members| grep -q #{node["slave_name"]}"
        shell = MClient.new(ctx, "execute_shell_command", [node["id"]], timeout=120, retries=1)
        result = shell.execute(:cmd => cmd).first.results
        if result[:data][:exit_code].to_i != 0
          Astute.logger.debug("There is no ceph installed or node is not in ceph mons")
          return answer
        end
        #remove the node from ceph mons
        shell.execute(:cmd => "ceph mon remove #{node["slave_name"]}").first.results
      end

      answer

    end

  end
end


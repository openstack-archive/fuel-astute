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
  module PreDelete

    def self.check_ceph_osds(ctx, nodes)
      answer = {"status" => "ready"}
      ceph_nodes = nodes.select { |n| n['roles'].include? 'ceph-osd' }
      ceph_osds = ceph_nodes.collect{ |n| n["id"] }
      return answer if ceph_osds.empty?

      Astute.logger.debug "Checking for running OSDs on nodes: #{ceph_osds}"

      shell = MClient.new(ctx, "execute_shell_command", ceph_osds, check_result=true, timeout=10, retries=1)
      mco_result = shell.execute(:cmd => 'pgrep -c ceph-osd')

      error_nodes = []
      result = mco_result.each do |n|
        if n.results[:data][:stdout].to_i != 0
          error_nodes << n[:sender]
        end
      end

      if not error_nodes.empty?
        msg = "Ceph OSDs are still running on nodes: #{error_nodes}. You must stop the OSDs manaully to delete these nodes."
        answer = {'status' => 'error', 'error' => msg}
      end

      answer
    end

  end
end


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
  class UpdateNoQuorumPolicy < PostDeployAction

    def process(deployment_info, context)
      # NOTE(bogdando) use 'suicide' if fencing is enabled in corosync
      xml = <<-EOF
      <diff>
        <diff-removed>
          <cib>
            <configuration>
              <crm_config>
                <cluster_property_set id="cib-bootstrap-options">
                  <nvpair value="ignore" id="cib-bootstrap-options-no-quorum-policy"/>
                </cluster_property_set>
              </crm_config>
            </configuration>
          </cib>
        </diff-removed>
        <diff-added>
          <cib>
            <configuration>
              <crm_config>
                <cluster_property_set id="cib-bootstrap-options">
                  <nvpair value="stop" id="cib-bootstrap-options-no-quorum-policy"/>
                </cluster_property_set>
              </crm_config>
            </configuration>
          </cib>
        </diff-added>
      </diff>
      EOF
      cmd = "/usr/sbin/cibadmin --patch --sync-call --xml-text #{xml}"

      controllers_count = deployment_info.select {|n|
        ['controller', 'primary-controller'].include? n['role']
      }.size
      if controllers_count > 2
        Astute.logger.info "Started updating no quorum policy for corosync cluster"
        primary_controller = deployment_info.find {|n| n['role'] == 'primary-controller' }

        response = run_shell_command(context, Array(primary_controller['uid']), cmd)
        if response[:data][:exit_code] != 0
          Astute.logger.warn "#{context.task_id}: Failed to update no "\
                               "quorum policy for corosync cluster,"
        end
        Astute.logger.info "#{context.task_id}: Finished updating "\
                           "no quorum policy for corosync cluster"
      else
        Astute.logger.info "No need to update quorum policy for corosync cluster"
      end
    end #process
  end #class
end

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
  class PrePatchingHa < PreNodeAction

    def process(deployment_info, context)
      return
      return if deployment_info.first['openstack_version_prev'].nil? ||
                deployment_info.first['deployment_mode'] !~ /ha/i

      # Run only once for node. If one of role is controller or primary-controller
      # generate new deployment_info block.
      # Important for 'mongo' role which run early then 'controller'
      current_uids = deployment_info.map{ |n| n['uid'] }
      controllers = deployment_info.first['nodes'].select{ |n| current_uids.include?(n['uid']) && n['role'] =~ /controller/i }
      c_deployment_info = deployment_info.select { |d_i| controllers.map{ |n| n['uid'] }.include? d_i['uid'] }

      return if c_deployment_info.empty?
      c_deployment_info.each do |c_d_i|
        c_d_i['role'] = controllers.find{ |c| c['uid'] == c_d_i['uid'] }['role']
      end
      controller_nodes = c_deployment_info.map{ |n| n['uid'] }

      Astute.logger.info "Starting migration of pacemaker services from " \
        "nodes #{controller_nodes.inspect}"

      Astute::Pacemaker.commands(action='stop', c_deployment_info).each do |pcmk_ban_cmd|
        response = run_shell_command(context, controller_nodes, pcmk_ban_cmd)

        if response[:data][:exit_code] != 0
          Astute.logger.warn "#{context.task_id}: Failed to ban service, "\
                             "check the debugging output for details"
        end
      end

      Astute.logger.info "#{context.task_id}: Finished pre-patching-ha hook"
    end #process
  end #class
end

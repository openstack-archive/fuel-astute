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

  class CirrosError < AstuteError; end

  class UploadCirrosImage < PostDeploymentAction

    def process(deployment_info, context)
      #FIXME: update context status to multirole support: possible situation where one of the
      #       roles of node fail but if last status - success, we try to run code below.

      node = deployment_info.last
      controller = node['nodes'].find { |n| n['role'] == 'primary-controller' }
      controller = node['nodes'].find { |n| n['role'] == 'controller' } unless controller

      if controller.nil?
        Astute.logger.debug "Could not find controller in nodes in facts! Please check logs to be su
re that it is correctly generated."
        return
      end
      # controller['test_vm_image'] contains a hash like that:
      # controller['test_vm_image'] = {
      # 'disk_format'       => 'qcow2',
      # 'container_format'  => 'bare',
      # 'public'            => 'true',
      # 'img_name'          => 'TestVM',
      # 'os_name'           => 'cirros',
      # 'img_path'          => '/opt/vm/cirros-x86_64-disk.img',
      # 'glance_properties' => '--property murano_image_info=\'{\"title\": \"Murano Demo\", \"type\": \"cirros.demo\"}\''
      # }

      os = node['test_vm_image']

      cmd = ". /root/openrc && /usr/bin/glance index"
      response = run_shell_command(context, Array(controller['uid']), cmd)
      if response[:data][:exit_code] != 0
        raise_cirros_error(
          context,
          node,
          'Disabling the upload of disk image because glance was not installed properly'
        )
      end

      cmd = ". /root/openrc && /usr/bin/glance index | grep #{os['img_name']}"
      response = run_shell_command(context, Array(controller['uid']), cmd)
      if response[:data][:exit_code] == 0
        Astute.logger.debug "Image \"#{os['img_name']}\" already added to stack"
      else
        cmd = ". /root/openrc && \
                 /usr/bin/glance image-create \
                 --name \'#{os['img_name']}\' \
                 --is-public #{os['public']} \
                 --container-format=\'#{os['container_format']}\' \
                 --disk-format=\'#{os['disk_format']}\' \
                 --min-ram=#{os['min_ram']} \
                 #{os['glance_properties']} \
                 --file \'#{os['img_path']}\' \
              "
        response = run_shell_command(context, Array(controller['uid']), cmd)
        if response[:data][:exit_code] == 0
          Astute.logger.info("#{context.task_id}: Upload cirros image \"#{os['img_name']}\" is done")
        else
          #raise_cirros_error(context, node, "Upload cirros \"#{os['img_name']}\" image failed")
          return
        end
      end
    end # process

    private

    def raise_cirros_error(context, node, msg='')
      Astute.logger.error("#{context.task_id}: #{msg}")
      context.report_and_update_status('nodes' => [
                                        {'uid' => node['uid'],
                                         'status' => 'error',
                                         'error_type' => 'deploy',
                                         'role' => node['role']
                                        }
                                       ]
                                      )
      raise CirrosError, msg
    end

  end # class
end

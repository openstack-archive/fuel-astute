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
      # Mark controller node as error if present
      node = deployment_info.find { |n| n['role'] == 'primary-controller' }
      node = deployment_info.find { |n| n['role'] == 'controller' } unless node
      node = deployment_info.last unless node

      controller = node['nodes'].find { |n| n['role'] == 'primary-controller' }
      controller = node['nodes'].find { |n| n['role'] == 'controller' } unless controller

      if controller.nil?
        Astute.logger.debug "Could not find controller in nodes in facts! " \
          "Please check logs to be sure that it is correctly generated."
        return
      end
      # controller['test_vm_image'] contains a hash like that:
      # controller['test_vm_image'] = {
      # 'disk_format'       => 'qcow2',
      # 'container_format'  => 'bare',
      # 'public'            => 'true',
      # 'img_name'          => 'TestVM',
      # 'os_name'           => 'cirros',
      # 'img_path'          => '/opt/vm/cirros-x86_64-disk.img'
      # }

      os = node['test_vm_image']
      cmd = ". /root/openrc && /usr/bin/glance image-list"

      # waited until the glance is started because when vCenter used as a glance
      # backend launch may takes up to 1 minute.
      response = {}
      5.times.each do |retries|
        sleep 10 if retries > 0

        response = run_shell_command(context, Array(controller['uid']), cmd)
        break if response[:data][:exit_code] == 0
      end

      if response[:data][:exit_code] != 0
        msg = 'Disabling the upload of disk image because glance was not installed properly'
        if context.status[node['uid']] != 'error'
          raise_cirros_error(
            context,
            node,
            msg
          )
        else
          Astute.logger.error("#{context.task_id}: #{msg}")
          return
        end
      end

      cmd = <<-UPLOAD_IMAGE
        . /root/openrc &&
        /usr/bin/glance image-list | grep -q #{os['img_name']} ||
        /usr/bin/glance image-create
          --name \'#{os['img_name']}\'
          --is-public #{os['public']}
          --container-format=\'#{os['container_format']}\'
            --disk-format=\'#{os['disk_format']}\'
            --min-ram=#{os['min_ram']}
            --file \'#{os['img_path']}\'
      UPLOAD_IMAGE
      cmd.tr!("\n"," ")

      response = run_shell_command(context, Array(controller['uid']), cmd)
      if response[:data][:exit_code] == 0
        Astute.logger.info "#{context.task_id}: Upload cirros " \
          "image \"#{os['img_name']}\" is done"
      else
        raise_cirros_error(context, node, "Upload cirros \"#{os['img_name']}\" image failed")
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

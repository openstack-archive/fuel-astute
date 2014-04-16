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

  class UploadCirrosImage < PostDeployAction

    def process(deployment_info, context)
      #FIXME: update context status to multirole support: possible situation where one of the
      #       roles of node fail but if last status - success, we try to run code below.
      if context.status.has_value?('error')
        Astute.logger.warn "Disabling the upload of disk image because deploy ended with an error"
        return
      end

      controller = deployment_info.find { |n| n['role'] == 'primary-controller' }
      controller = deployment_info.find { |n| n['role'] == 'controller' } unless controller
      if controller.nil?
        Astute.logger.debug("Could not find controller! Possible adding a new node to the existing cluster?")
        return
      end

      os = {
        'os_tenant_name'    => Shellwords.escape("#{controller['access']['tenant']}"),
        'os_username'       => Shellwords.escape("#{controller['access']['user']}"),
        'os_password'       => Shellwords.escape("#{controller['access']['password']}"),
        'os_auth_url'       => "http://#{controller['management_vip'] || '127.0.0.1'}:5000/v2.0/",
        'disk_format'       => 'qcow2',
        'container_format'  => 'bare',
        'public'            => 'true',
        'img_name'          => 'TestVM',
        'os_name'           => 'cirros'
      }

      os['img_path'] = case controller['cobbler']['profile']
                         when 'centos-x86_64'
                           '/opt/vm/cirros-x86_64-disk.img'
                         when 'ubuntu_1204_x86_64'
                           '/usr/share/cirros-testvm/cirros-x86_64-disk.img'
                         else
                           raise CirrosError, "Unknown system #{controller['cobbler']['profile']}"
                       end
      auth_params = "-N #{os['os_auth_url']} \
                     -T #{os['os_tenant_name']} \
                     -I #{os['os_username']} \
                     -K #{os['os_password']}"
      cmd = "/usr/bin/glance #{auth_params} \
              index && \
             (/usr/bin/glance #{auth_params} \
              index | grep #{os['img_name']})"
      response = run_shell_command(context, Array(controller['uid']), cmd)
      if response[:data][:exit_code] == 0
        Astute.logger.debug "Image already added to stack"
      else
        cmd = "/usr/bin/glance #{auth_params} \
               image-create \
                 --name \'#{os['img_name']}\' \
                 --is-public #{os['public']} \
                 --container-format=\'#{os['container_format']}\' \
                 --disk-format=\'#{os['disk_format']}\' \
                 --property murano_image_info=\'{\"title\": \"Murano Demo\", \"type\": \"cirros.demo\"}\' \
                 --file \'#{os['img_path']}\' \
              "
        response = run_shell_command(context, Array(controller['uid']), cmd)
        if response[:data][:exit_code] == 0
          Astute.logger.info("#{context.task_id}: Upload cirros image is done")
        else
          msg = 'Upload cirros image failed'
          Astute.logger.error("#{context.task_id}: #{msg}")
          context.report_and_update_status('nodes' => [
                                            {'uid' => controller['uid'],
                                             'status' => 'error',
                                             'error_type' => 'deploy',
                                             'role' => controller['role']
                                            }
                                           ]
                                          )
          raise CirrosError, msg
        end
      end
    end # process
  end # class
end
#    Copyright 2014 Mirantis, Inc.
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

require 'popen4'
require 'fileutils'

module Astute
  class GenerateSshKeys < PreDeploymentAction

    # Generate ssh keys to future uploading to all cluster nodes
    def process(deployment_info, context)
      overwrite = false
      deployment_id = deployment_info.first['deployment_id']
      raise "Deployment_id is missing" unless deployment_id

      Astute.config.PUPPET_SSH_KEYS.each do |key_name|
        dir_path = File.join(Astute.config.PUPPET_SSH_KEYS_DIR, deployment_id.to_s, key_name)
        key_path = File.join(dir_path, key_name)

        FileUtils.mkdir_p dir_path
        raise DeploymentEngineError, "Could not create directory #{dir_path}" unless File.directory?(dir_path)

        next if File.exist?(key_path) && !overwrite

        # Generate 2 keys(<name> and <name>.pub) and save it to <KEY_DIR>/<name>/
        File.delete key_path if File.exist? key_path

        cmd = "ssh-keygen -b 2048 -t rsa -N '' -f #{key_path} 2>&1"
        status, stdout, _stderr = run_system_command cmd

        error_msg = "Could not generate ssh key! Command: #{cmd}, output: #{stdout}, exit code: #{status}"
        raise DeploymentEngineError, error_msg if status != 0
      end
    end #process

    private

    def run_system_command(cmd)
      pid, _, stdout, stderr = Open4::popen4 cmd
      _, status = Process::waitpid2 pid
      return status.exitstatus, stdout, stderr
    end

  end #class
end

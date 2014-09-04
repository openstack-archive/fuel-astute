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
  class DeployActions

    def initialize(deployment_info, context)
      @deployment_info = deployment_info
      @context = context
      @actions = []
    end

    def process
      @actions.each { |action| action.process(@deployment_info, @context) }
    end
  end

  class PreDeployActions < DeployActions

    def initialize(deployment_info, context)
      super
      @actions = [
        PrePatchingHa.new,
        PrePatching.new
      ]
    end

  end

  class PostDeployNodeActions < DeployActions

    def initialize(deployment_info, context)
      super
      @actions = [
        PostPatchingHa.new
      ]
    end

  end


  class PostDeployActions < DeployActions

    def initialize(deployment_info, context)
      super
      @actions = [
        UpdateNoQuorumPolicy.new,
        UploadCirrosImage.new,
        RestartRadosgw.new,
        UpdateClusterHostsInfo.new
      ]
    end

  end


  class DeployAction

    def process(deployment_info, context)
      raise "Should be implemented!"
    end

    def run_shell_command(context, node_uids, cmd, timeout=60)
      shell = MClient.new(context,
                          'execute_shell_command',
                          node_uids,
                          check_result=true,
                          timeout=timeout,
                          retries=1)

      #TODO: return result for all nodes not only for first
      response = shell.execute(:cmd => cmd).first
      Astute.logger.debug("#{context.task_id}: cmd: #{cmd}
                                               stdout: #{response[:data][:stdout]}
                                               stderr: #{response[:data][:stderr]}
                                               exit code: #{response[:data][:exit_code]}")
      response
    rescue MClientTimeout, MClientError => e
      Astute.logger.error("#{context.task_id}: cmd: #{cmd}
                                               mcollective error: #{e.message}")
      {:data => {}}
    end
  end

  class PreDeployAction < DeployAction; end
  class PostDeployAction < DeployAction; end
  class PostDeployNodeAction < DeployAction; end

end

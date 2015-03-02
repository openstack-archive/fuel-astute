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
        ConnectFacts.new
      ]
    end
  end

  class GranularPreDeployActions < DeployActions
    def initialize(deployment_info, context)
      super
      @actions = [
        ConnectFacts.new
      ]
    end
  end

  class PostDeployActions < DeployActions
    def initialize(deployment_info, context)
      super
      @actions = [
        PostPatchingHa.new
      ]
    end
  end

  class GranularPostDeployActions < DeployActions
    def initialize(deployment_info, context)
      super
      @actions = [
        PostPatchingHa.new
      ]
    end
  end

  class PreNodeActions

    def initialize(context)
      @node_uids = []
      @context = context
      @actions = [
        PrePatchingHa.new,
        StopOSTServices.new,
        PrePatching.new
      ]
    end

    def process(deployment_info)
      nodes_to_process = deployment_info.select { |n| !@node_uids.include?(n['uid']) }
      return if nodes_to_process.empty?

      @actions.each { |action| action.process(nodes_to_process, @context) }
      @node_uids += nodes_to_process.map { |n| n['uid'] }
    end
  end

  class GranularPreNodeActions

    def initialize(context)
      @node_uids = []
      @context = context
      @actions = [
        PrePatchingHa.new,
        StopOSTServices.new,
        PrePatching.new
      ]
    end

    def process(deployment_info)
      nodes_to_process = deployment_info.select { |n| !@node_uids.include?(n['uid']) }
      return if nodes_to_process.empty?

      @actions.each { |action| action.process(nodes_to_process, @context) }
      @node_uids += nodes_to_process.map { |n| n['uid'] }
    end
  end

  class PreDeploymentActions < DeployActions

    def initialize(deployment_info, context)
      super
      @actions = [
        SyncTime.new,
        GenerateSshKeys.new,
        GenerateKeys.new,
        UploadSshKeys.new,
        UploadKeys.new,
        UpdateRepoSources.new,
        SyncPuppetStuff.new,
        SyncTasks.new,
        EnablePuppetDeploy.new,
        UploadFacts.new
      ]
    end

  end

  class GranularPreDeploymentActions < DeployActions

    def initialize(deployment_info, context)
      super
      @actions = [
        EnablePuppetDeploy.new,
        UploadFacts.new
      ]
    end

  end

  class PostDeploymentActions < DeployActions

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

    def only_uniq_nodes(nodes)
      nodes.uniq { |n| n['uid'] }
    end

    # Prevent high load for tasks
    def perform_with_limit(nodes, &block)
      nodes.each_slice(Astute.config[:max_nodes_per_call]) do |part|
        block.call(part)
      end
    end

  end # DeployAction

  class PreDeployAction < DeployAction; end
  class PostDeployAction < DeployAction; end
  class PreNodeAction < DeployAction; end
  class PostNodeAction < DeployAction; end
  class PreDeploymentAction < DeployAction; end
  class PostDeploymentAction < DeployAction; end

end

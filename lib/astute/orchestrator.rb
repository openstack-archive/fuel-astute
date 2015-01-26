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

  class Orchestrator
    def initialize(log_parsing=false)
      @log_parsing = log_parsing
    end

    def node_type(reporter, task_id, nodes_uids, timeout=nil)
        provisioner = Provisioner.new(@log_parsing)
        provisioner.node_type(reporter, task_id, nodes_uids, timeout)
    end

    def execute_tasks(up_reporter, task_id, tasks)
      ctx = Context.new(task_id, up_reporter)
      Astute::NailgunHooks.new(tasks, ctx, 'execute_tasks').process
      report_result({}, up_reporter)
    end

    def deploy(up_reporter, task_id, deployment_info, pre_deployment=[], post_deployment=[])
      deploy_cluster(
        up_reporter,
        task_id,
        deployment_info,
        Astute::DeploymentEngine::NailyFact,
        pre_deployment,
        post_deployment
      )
    end

    def task_deployment(up_reporter, task_id, deployment_info, pre_deployment=[], post_deployment=[])
      deploy_cluster(
        up_reporter,
        task_id,
        deployment_info,
        Astute::DeploymentEngine::Tasklib,
        pre_deployment,
        post_deployment
      )
    end

    def granular_deploy(up_reporter, task_id, deployment_info, pre_deployment=[], post_deployment=[])
      deploy_cluster(
        up_reporter,
        task_id,
        deployment_info,
        Astute::DeploymentEngine::GranularDeployment,
        pre_deployment,
        post_deployment
      )
    end

    def provision(reporter, task_id, engine_attrs, nodes)
        provisioner = Provisioner.new(@log_parsing)
        provisioner.provision(reporter, task_id, engine_attrs, nodes)
    end

    def remove_nodes(reporter, task_id, engine_attrs, nodes, reboot=true, raise_if_error=false)
        provisioner = Provisioner.new(@log_parsing)
        provisioner.remove_nodes(reporter, task_id, engine_attrs, nodes, reboot, raise_if_error)
    end

    def stop_puppet_deploy(reporter, task_id, nodes)
      nodes_uids = nodes.map { |n| n['uid'] }.uniq
      puppetd = MClient.new(Context.new(task_id, reporter), "puppetd", nodes_uids, check_result=false)
      puppetd.stop_and_disable
    end

    def stop_provision(reporter, task_id, engine_attrs, nodes)
        provisioner = Provisioner.new(@log_parsing)
        provisioner.stop_provision(reporter, task_id, engine_attrs, nodes)
    end

    def dump_environment(reporter, task_id, settings)
      Dump.dump_environment(Context.new(task_id, reporter), settings)
    end

    def verify_networks(reporter, task_id, nodes)
      ctx = Context.new(task_id, reporter)
      validate_nodes_access(ctx, nodes)
      Network.check_network(ctx, nodes)
    end

    def check_dhcp(reporter, task_id, nodes)
      ctx = Context.new(task_id, reporter)
      validate_nodes_access(ctx, nodes)
      Network.check_dhcp(ctx, nodes)
    end

    def multicast_verification(reporter, task_id, nodes)
      ctx = Context.new(task_id, reporter)
      validate_nodes_access(ctx, nodes)
      Network.multicast_verification(ctx, nodes)
    end

    private

    def deploy_cluster(up_reporter, task_id, deployment_info, deploy_engine, pre_deployment, post_deployment)
      proxy_reporter = ProxyReporter::DeploymentProxyReporter.new(up_reporter, deployment_info)
      log_parser = @log_parsing ? LogParser::ParseDeployLogs.new : LogParser::NoParsing.new
      context = Context.new(task_id, proxy_reporter, log_parser)
      deploy_engine_instance = deploy_engine.new(context)
      Astute.logger.info "Using #{deploy_engine_instance.class} for deployment."

      deploy_engine_instance.deploy(deployment_info, pre_deployment, post_deployment)

      context.status
    end

    def report_result(result, reporter)
      default_result = {'status' => 'ready', 'progress' => 100}

      result = {} unless result.instance_of?(Hash)
      status = default_result.merge(result)
      reporter.report(status)
    end

    def validate_nodes_access(ctx, nodes)
      nodes_types = node_type(ctx.reporter, ctx.task_id, nodes.map{ |n| n['uid'] }, timeout=10)
      not_avaliable_nodes = nodes.map { |n| n['uid'].to_s } - nodes_types.map { |n| n['uid'].to_s }
      unless not_avaliable_nodes.empty?
        raise "Network verification not avaliable because nodes #{not_avaliable_nodes} " \
          "not avaliable via mcollective"
      end
    end

  end # class
end # module

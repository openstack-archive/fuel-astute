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


    # Deprecated deploy method. Use monolitic site.pp. Do not use from 7.1.
    # Report progress based on puppet logs
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

    # Deploy method which use small tasks, but run block of tasks for role
    # instead of run it using full graph. Use from 7.1 to 8.0. Report progress
    # based on puppet logs
    def granular_deploy(up_reporter, task_id, deployment_info, pre_deployment=[], post_deployment=[])
      time_start = Time.now.to_i
      deploy_cluster(
        up_reporter,
        task_id,
        deployment_info,
        Astute::DeploymentEngine::GranularDeployment,
        pre_deployment,
        post_deployment
      )
    ensure
      Astute.logger.info "Deployment summary: time was spent " \
        "#{time_summary(time_start)}"
    end

    # Deploy method which use small tasks in full graph.
    # Use from 8.0 (experimental). Report progress based on tasks
    def task_deploy(up_reporter, task_id, deployment_info, deployment_tasks)
      time_start = Time.now.to_i
      proxy_reporter = ProxyReporter::TaskProxyReporter.new(
        up_reporter,
        deployment_tasks.keys
      )
      context = Context.new(task_id, proxy_reporter)
      Astute.logger.info "Task based deployment will be used"

      deployment_engine = TaskDeployment.new(context)
      deployment_engine.deploy(deployment_info, deployment_tasks)
    ensure
      Astute.logger.info "Deployment summary: time was spent " \
        "#{time_summary(time_start)}"
    end

    def provision(up_reporter, task_id, provisioning_info, provision_method)
      time_start = Time.now.to_i
      proxy_reporter = ProxyReporter::ProvisiningProxyReporter.new(
        up_reporter,
        provisioning_info
      )
      provisioner = Provisioner.new(@log_parsing)
      if provisioning_info['pre_provision']
        image_build_log = "/var/log/fuel-agent-env" \
          "-#{calculate_cluster_id(provisioning_info)}.log"
        Astute.logger.info "Please check image build log here: " \
          "#{image_build_log}"
        ctx = Context.new(task_id, proxy_reporter)
        provisioner.report_image_provision(
          proxy_reporter,
          task_id,
          provisioning_info['nodes'],
          image_log_parser(provisioning_info)
        ) do
          begin
            Astute::NailgunHooks.new(
              provisioning_info['pre_provision'],
              ctx,
              'provision'
            ).process
          rescue Astute::DeploymentEngineError => e
            raise e, "Image build task failed. Please check " \
              "build log here for details: #{image_build_log}. " \
              "Hint: restart deployment can help if no error in build " \
              "log was found"
          end
        end
      end

      # NOTE(kozhukalov): Some of our pre-provision tasks need cobbler to be synced
      # once those tasks are finished. It looks like the easiest way to do this
      # inside mcollective docker container is to use Astute binding capabilities.
      cobbler = CobblerManager.new(provisioning_info['engine'], up_reporter)
      cobbler.sync

      provisioner.provision(
        proxy_reporter,
        task_id,
        provisioning_info,
        provision_method
      )
    ensure
      Astute.logger.info "Provision summary: time was spent " \
        "#{time_summary(time_start)}"
    end

    def remove_nodes(reporter, task_id, engine_attrs, nodes, options={})
      # FIXME(vsharshov): bug/1463881: In case of post deployment we mark all nodes
      # as ready. In this case we will get empty nodes.
      return if nodes.empty?

      options.reverse_merge!({
        :reboot => true,
        :raise_if_error => false,
        :reset => false
      })

      result = perform_pre_deletion_tasks(reporter, task_id, nodes, options)
      return result if result['status'] != 'ready'

      provisioner = Provisioner.new(@log_parsing)
      provisioner.remove_nodes(
        reporter,
        task_id,
        engine_attrs,
        nodes,
        options
      )
    end

    def stop_puppet_deploy(reporter, task_id, nodes)
      # FIXME(vsharshov): bug/1463881: In case of post deployment we mark all nodes
      # as ready. If we run stop deployment we will get empty nodes.
      return if nodes.empty?

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

    def check_repositories(reporter, task_id, nodes, urls)
      ctx = Context.new(task_id, reporter)
      validate_nodes_access(ctx, nodes)
      Network.check_urls_access(ctx, nodes, urls)
    end

    def check_repositories_with_setup(reporter, task_id, nodes)
      ctx = Context.new(task_id, reporter)
      validate_nodes_access(ctx, nodes)
      Network.check_repositories_with_setup(ctx, nodes)
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

    def image_log_parser(provisioning_info)
      log_parser = LogParser::ParseImageBuildLogs.new
      log_parser.cluster_id = calculate_cluster_id(provisioning_info)
      log_parser
    end

    def calculate_cluster_id(provisioning_info)
      return nil unless provisioning_info['pre_provision'].present?
      cmd = provisioning_info['pre_provision'].first.fetch('parameters', {}).fetch('cmd', "")
      # find cluster id from cmd using pattern fuel-agent-env-<Integer>.log
      # FIXME(vsharshov): https://bugs.launchpad.net/fuel/+bug/1449512
      cluster_id = cmd[/fuel-agent-env-(\d+)/, 1]
      Astute.logger.debug "Cluster id: #{cluster_id}"
      cluster_id
    end

    def check_for_offline_nodes(reporter, task_id, nodes)
      PreDelete.check_for_offline_nodes(Context.new(task_id, reporter), nodes)
    end

    def check_ceph_osds(reporter, task_id, nodes)
      PreDelete.check_ceph_osds(Context.new(task_id, reporter), nodes)
    end

    def remove_ceph_mons(reporter, task_id, nodes)
      PreDelete.remove_ceph_mons(Context.new(task_id, reporter), nodes)
    end

    def perform_pre_deletion_tasks(reporter, task_id, nodes, options={})
      result = {'status' => 'ready'}
      # This option is no longer Ceph-specific and should be renamed
      # FIXME(rmoe): https://bugs.launchpad.net/fuel/+bug/1454377
      if options[:check_ceph]
        result = check_for_offline_nodes(reporter, task_id, nodes)
        return result if result['status'] != 'ready'
        result = check_ceph_osds(reporter, task_id, nodes)
        return result if result['status'] != 'ready'
        result = remove_ceph_mons(reporter, task_id, nodes)
      end
      result
    end

    def time_summary(time)
      amount_time = (Time.now.to_i - time).to_i
      Time.at(amount_time).utc.strftime("%H:%M:%S")
    end

  end # class
end # module

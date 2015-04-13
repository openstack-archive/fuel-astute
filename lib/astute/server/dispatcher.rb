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

require 'astute/server/reporter'

module Astute
  module Server

    class Dispatcher
      def initialize(producer)
        @orchestrator = Astute::Orchestrator.new(log_parsing=true)
        @producer = producer
        @provisionLogParser = Astute::LogParser::ParseProvisionLogs.new
      end

      def echo(args)
        Astute.logger.info 'Running echo command'
        args
      end

      #
      #  Main worker actions
      #

      def image_provision(data)
        provision(data, 'image')
      end

      def native_provision(data)
        provision(data, 'native')
      end

      def provision(data, provision_method)

        Astute.logger.info("'provision' method called with data: #{data.inspect}")

        reporter = Astute::Server::Reporter.new(@producer, data['respond_to'], data['args']['task_uuid'])
        begin
          result = @orchestrator.provision(
            reporter,
            data['args']['task_uuid'],
            data['args']['provisioning_info'],
            provision_method
          )

        #TODO(vsharshov): Refactoring the deployment aborting messages (StopIteration)
        rescue => e
          Astute.logger.error "Error running provisioning: #{e.message}, trace: #{e.format_backtrace}"
          raise StopIteration
        end
        raise StopIteration if result && result['status'] == 'error'
      end

      def deploy(data)
        Astute.logger.info("'deploy' method called with data: #{data.inspect}")

        reporter = Astute::Server::Reporter.new(@producer, data['respond_to'], data['args']['task_uuid'])

        begin
          @orchestrator.deploy(
            reporter,
            data['args']['task_uuid'],
            data['args']['deployment_info'],
            data['args']['pre_deployment'] || [],
            data['args']['post_deployment'] || []
          )
          reporter.report('status' => 'ready', 'progress' => 100)
        rescue Timeout::Error
          msg = "Timeout of deployment is exceeded."
          Astute.logger.error msg
          reporter.report('status' => 'error', 'error' => msg)
        end
      end

      def task_deployment(data)
        Astute.logger.info("'task_deployment' method called with data: #{data.inspect}")

        reporter = Astute::Server::Reporter.new(@producer, data['respond_to'], data['args']['task_uuid'])
        begin
          @orchestrator.task_deployment(
            reporter,
            data['args']['task_uuid'],
            data['args']['deployment_info'],
            data['args']['pre_deployment'] || [],
            data['args']['post_deployment'] || []
          )
          reporter.report('status' => 'ready', 'progress' => 100)
        rescue Timeout::Error
          msg = "Timeout of deployment is exceeded."
          Astute.logger.error msg
          reporter.report('status' => 'error', 'error' => msg)
        end
      end

      def granular_deploy(data)
        Astute.logger.info("'granular_deploy' method called with data: #{data.inspect}")

        reporter = Astute::Server::Reporter.new(@producer, data['respond_to'], data['args']['task_uuid'])
        begin
          @orchestrator.granular_deploy(
            reporter,
            data['args']['task_uuid'],
            data['args']['deployment_info'],
            data['args']['pre_deployment'] || [],
            data['args']['post_deployment'] || []
          )
          reporter.report('status' => 'ready', 'progress' => 100)
        rescue Timeout::Error
          msg = "Timeout of deployment is exceeded."
          Astute.logger.error msg
          reporter.report('status' => 'error', 'error' => msg)
        end
      end

      def verify_networks(data)
        data.fetch('subtasks', []).each do |subtask|
          if self.respond_to?(subtask['method'])
            self.send(subtask['method'], subtask)
          else
            Astute.logger.warn("No method for #{subtask}")
          end
        end
        reporter = Astute::Server::Reporter.new(@producer, data['respond_to'], data['args']['task_uuid'])
        result = @orchestrator.verify_networks(reporter, data['args']['task_uuid'], data['args']['nodes'])
        report_result(result, reporter)
      end

      def check_dhcp(data)
        reporter = Astute::Server::Reporter.new(@producer, data['respond_to'], data['args']['task_uuid'])
        result = @orchestrator.check_dhcp(reporter, data['args']['task_uuid'], data['args']['nodes'])
        report_result(result, reporter)
      end

      def multicast_verification(data)
        reporter = Astute::Server::Reporter.new(@producer, data['respond_to'], data['args']['task_uuid'])
        result = @orchestrator.multicast_verification(reporter, data['args']['task_uuid'], data['args']['nodes'])
        report_result(result, reporter)
      end

      def dump_environment(data)
        task_id = data['args']['task_uuid']
        reporter = Astute::Server::Reporter.new(@producer, data['respond_to'], task_id)
        @orchestrator.dump_environment(reporter, task_id, data['args']['settings'])
      end

      def remove_nodes(data)
        task_uuid = data['args']['task_uuid']
        reporter = Astute::Server::Reporter.new(@producer, data['respond_to'], task_uuid)
        nodes = data['args']['nodes']
        engine = data['args']['engine']

        # Only run the check for DeletionTask, not for ClusterDeletionTask
        if data['respond_to'] == 'remove_nodes_resp'
          result = @orchestrator.check_ceph_osds(reporter, task_uuid, nodes)
        else
          result = {'status' => 'ready'}
        end

        if result["status"] == "ready"
          if nodes.empty?
            Astute.logger.debug("#{task_uuid} Node list is empty")
            result = nil
          else
            result = @orchestrator.remove_nodes(reporter, task_uuid, engine, nodes)
          end
        end

        report_result(result, reporter)
      end

      def reset_environment(data)
        remove_nodes(data)
      end

      def execute_shell(data)
        Astute.logger.info("'execute_shell' method called with data: #{data.inspect}")

        reporter = Astute::Server::Reporter.new(@producer, data['respond_to'], data['args']['task_uuid'])

        begin
          shell = MClient.new(Context.new(data['args']['task_uuid'], reporter),
                              'execute_shell_command',
                              data['args']['node_ids'],
                              check_result=false,
                              timeout=data['args']['timeout'])

          mco_result = shell.execute(:cmd => data['args']['cmd'])

          result = mco_result.map do |n|
            {
              'uid'       => n.results[:sender],
              'exit code' => n.results[:data][:exit_code]
            }
          end

          reporter.report('status' => 'ready', 'progress' => 100, 'msg' => result)
        rescue Timeout::Error
          msg = "Timeout of deployment is exceeded."
          Astute.logger.error msg
          reporter.report('status' => 'error', 'error' => msg)
        end
      end

      def execute_tasks(data)
        task_uuid = data['args']['task_uuid']
        reporter = Astute::Server::Reporter.new(
          @producer,
          data['respond_to'],
          task_uuid
        )

        @orchestrator.execute_tasks(
          reporter,
          task_uuid,
          data['args']['tasks']
        )
      end

      #
      #  Service worker actions
      #

      def stop_deploy_task(data, service_data)
        Astute.logger.debug("'stop_deploy_task' service method called with data: #{data.inspect}")
        target_task_uuid = data['args']['stop_task_uuid']
        task_uuid = data['args']['task_uuid']

        return unless task_in_queue?(target_task_uuid, service_data[:tasks_queue])

        Astute.logger.debug("Cancel task #{target_task_uuid}. Start")
        if target_task_uuid == service_data[:tasks_queue].current_task_id
          reporter = Astute::Server::Reporter.new(@producer, data['respond_to'], task_uuid)
          result = stop_current_task(data, service_data, reporter)
          report_result(result, reporter)
        else
          replace_future_task(data, service_data)
        end
      end

      private

      def task_in_queue?(task_uuid, tasks_queue)
        tasks_queue.task_in_queue?(task_uuid)
      end

      def replace_future_task(data, service_data)
        target_task_uuid = data['args']['stop_task_uuid']
        task_uuid = data['args']['task_uuid']

        new_task_data = data_for_rm_nodes(data)
        Astute.logger.info("Replace running task #{target_task_uuid} to new #{task_uuid} with data: #{new_task_data.inspect}")
        service_data[:tasks_queue].replace_task(target_task_uuid, new_task_data)
      end

      def stop_current_task(data, service_data, reporter)
        target_task_uuid = data['args']['stop_task_uuid']
        task_uuid = data['args']['task_uuid']
        nodes = data['args']['nodes']

        Astute.logger.info "Try to kill running task #{target_task_uuid}"
        service_data[:main_work_thread].kill

        result = if ['deploy', 'task_deployment', 'granular_deploy'].include? (
            service_data[:tasks_queue].current_task_method)
          @orchestrator.stop_puppet_deploy(reporter, task_uuid, nodes)
          @orchestrator.remove_nodes(reporter, task_uuid, data['args']['engine'], nodes)
        else
          @orchestrator.stop_provision(reporter, task_uuid, data['args']['engine'], nodes)
        end
      end

      def data_for_rm_nodes(data)
        data['method'] = 'remove_nodes'
        data
      end

      def report_result(result, reporter)
        result = {} unless result.instance_of?(Hash)
        status = {'status' => 'ready', 'progress' => 100}.merge(result)
        reporter.report(status)
      end
    end

  end #Server
end #Astute

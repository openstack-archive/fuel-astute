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

require 'astute/validator'

module Astute
  class Orchestrator
    def initialize(deploy_engine=nil, log_parsing=false)
      @deploy_engine = deploy_engine || Astute::DeploymentEngine::NailyFact
      @log_parsing = log_parsing
    end

    def node_type(reporter, task_id, nodes, timeout=nil)
      context = Context.new(task_id, reporter)
      uids = nodes.map {|n| n['uid']}
      systemtype = MClient.new(context, "systemtype", uids, check_result=false, timeout)
      systems = systemtype.get_type
      systems.map do |n|
        {
          'uid'       => n.results[:sender],
          'node_type' => n.results[:data][:node_type].chomp
        }
      end
    end

    def deploy(up_reporter, task_id, deployment_info)
      proxy_reporter = ProxyReporter::DeploymentProxyReporter.new(up_reporter, deployment_info)
      log_parser = @log_parsing ? LogParser::ParseDeployLogs.new : LogParser::NoParsing.new
      context = Context.new(task_id, proxy_reporter, log_parser)
      deploy_engine_instance = @deploy_engine.new(context)
      Astute.logger.info "Using #{deploy_engine_instance.class} for deployment."
      
      deploy_engine_instance.deploy(deployment_info)
      context.status
    end

    def provision(reporter, engine_attrs, nodes, strong_validation = true)
      raise "Nodes to provision are not provided!" if nodes.empty?
      validate_provision_attrs(engine_attrs, nodes, strong_validation)

      engine = create_engine(engine_attrs, reporter)
      begin
        add_nodes_to_cobbler(engine, nodes)
        reboot_events = reboot_nodes(engine, nodes)
        failed_nodes  = check_reboot_nodes(engine, reboot_events)
      rescue RuntimeError => e
        Astute.logger.error("Error occured while provisioning: #{e.inspect}")
        reporter.report({
                          'status' => 'error',
                          'error' => 'Cobbler error',
                          'progress' => 100
                        })
        raise e
      ensure
        engine.sync
      end

      if failed_nodes.empty?
        report_result({}, reporter)
      else
        Astute.logger.error("Nodes failed to reboot: #{failed_nodes.inspect}")
        reporter.report({
                          'status' => 'error',
                          'error' => "Nodes failed to reboot: #{failed_nodes.inspect}",
                          'progress' => 100
                        })
        raise e
      end
    end

    def watch_provision_progress(reporter, task_id, nodes)
      raise "Nodes to provision are not provided!" if nodes.empty?

      nodes_uids = nodes.map { |n| n['uid'] }

      provisionLogParser = @log_parsing ? LogParser::ParseProvisionLogs.new : LogParser::NoParsing.new
      proxy_reporter = ProxyReporter::DeploymentProxyReporter.new(reporter)
      sleep_not_greater_than(10) do # Wait while nodes going to reboot
        Astute.logger.info "Starting OS provisioning for nodes: #{nodes_uids.join(',')}"
        begin
          provisionLogParser.prepare(nodes)
        rescue => e
          Astute.logger.warn "Some error occurred when prepare LogParser: #{e.message}, trace: #{e.format_backtrace}"
        end
      end
      nodes_not_booted = nodes_uids.clone
      begin
        Timeout.timeout(Astute.config.PROVISIONING_TIMEOUT) do  # Timeout for booting target OS
          catch :done do
            while true
              sleep_not_greater_than(5) do
                types = node_type(proxy_reporter, task_id, nodes, 2)
                types.each { |t| Astute.logger.debug("Got node types: uid=#{t['uid']} type=#{t['node_type']}") }

                Astute.logger.debug("Not target nodes will be rejected")
                target_uids = types.reject{|n| n['node_type'] != 'target'}.map{|n| n['uid']}
                nodes_not_booted -= types.map { |n| n['uid'] }
                Astute.logger.debug "Not provisioned: #{nodes_not_booted.join(',')}, got target OSes: #{target_uids.join(',')}"

                if nodes.length == target_uids.length
                  Astute.logger.info "All nodes #{target_uids.join(',')} are provisioned."
                  throw :done
                else
                  Astute.logger.debug("Nodes list length is not equal to target nodes list length: #{nodes.length} != #{target_uids.length}")
                end

                report_about_progress(proxy_reporter, provisionLogParser, nodes_uids, target_uids, nodes)
              end
            end
          end
          # We are here if jumped by throw from while cycle
        end
      rescue Timeout::Error
        msg = "Timeout of provisioning is exceeded."
        Astute.logger.error msg
        error_nodes = nodes_not_booted.map { |n| {'uid' => n,
                                                  'status' => 'error',
                                                  'error_msg' => msg,
                                                  'progress' => 100,
                                                  'error_type' => 'provision'} }
        proxy_reporter.report({'status' => 'error', 'error' => msg, 'nodes' => error_nodes})
        return FAIL
      end

      nodes_progress = nodes.map do |n|
        {'uid' => n['uid'], 'progress' => 100, 'status' => 'provisioned'}
      end
      proxy_reporter.report({'nodes' => nodes_progress})
      return SUCCESS
    end

    def remove_nodes(reporter, task_id, nodes)
      NodesRemover.new(Context.new(task_id, reporter), nodes).remove
    end

    def dump_environment(reporter, task_id, lastdump)
      Dump.dump_environment(Context.new(task_id, reporter), lastdump)
    end

    def verify_networks(reporter, task_id, nodes)
      Network.check_network(Context.new(task_id, reporter), nodes)
    end

    def download_release(up_reporter, task_id, release_info)
      raise "Release information not provided!" if release_info.empty?

      attrs = {'deployment_mode' => 'rpmcache',
               'deployment_id' => 'rpmcache'}
      facts = {'rh_username' => release_info['username'],
               'rh_password' => release_info['password']}
      facts.merge!(attrs)

      if release_info['license_type'] == 'rhn'
        facts.merge!(
          {'use_satellite' => 'true',
           'sat_hostname' => release_info['satellite'],
           'activation_key' => release_info['activation_key']})
      end
      facts['uid'] = 'master'
      facts = [facts]
      proxy_reporter = ProxyReporter::DLReleaseProxyReporter.new(up_reporter, facts.size)
      #FIXME: These parameters should be propagated from Nailgun. Maybe they should be saved
      #       in Release.json.
      nodes_to_parser = [
        {:uid => 'master',
         :path_items => [
            {:max_size => 1111280705, :path => '/var/www/nailgun/rhel', :weight => 3},
            {:max_size => 195900000, :path => '/var/cache/yum/x86_64/6Server', :weight => 1},
         ]}
      ]
      log_parser = @log_parsing ? LogParser::DirSizeCalculation.new(nodes_to_parser) : LogParser::NoParsing.new
      context = Context.new(task_id, proxy_reporter, log_parser)
      deploy_engine_instance = @deploy_engine.new(context)
      Astute.logger.info "Using #{deploy_engine_instance.class} for release download."
      deploy_engine_instance.deploy_piece(facts, 0)
      proxy_reporter.report({'status' => 'ready', 'progress' => 100})
    end

    def check_redhat_credentials(reporter, task_id, credentials)
      ctx = Context.new(task_id, reporter)
      begin
        Astute::RedhatChecker.new(ctx, credentials).check_redhat_credentials
      rescue Astute::RedhatCheckingError => e
        Astute.logger.error("Error #{e.message}")
        raise StopIteration
      rescue => e
        Astute.logger.error("Unexpected error #{e.message} traceback #{e.format_backtrace}")
        raise e
      end
    end

    def check_redhat_licenses(reporter, task_id, credentials, nodes=nil)
      ctx = Context.new(task_id, reporter)
      begin
        Astute::RedhatChecker.new(ctx, credentials).check_redhat_licenses(nodes)
      rescue Astute::RedhatCheckingError => e
        Astute.logger.error("Error #{e.message}")
        raise StopIteration
      rescue => e
        Astute.logger.error("Unexpected error #{e.message} traceback #{e.format_backtrace}")
        raise e
      end
    end

    private

    def report_result(result, reporter)
      default_result = {'status' => 'ready', 'progress' => 100}

      result = {} unless result.instance_of?(Hash)
      status = default_result.merge(result)
      reporter.report(status)
    end

    def sleep_not_greater_than(sleep_time, &block)
      time = Time.now.to_f
      block.call
      time = time + sleep_time - Time.now.to_f
      sleep(time) if time > 0
    end

    def create_engine(engine_attrs, reporter)
      raise "Settings for Cobbler must be set" if engine_attrs.blank?
      
      begin
        Astute.logger.info("Trying to instantiate cobbler engine: #{engine_attrs.inspect}")
        Astute::Provision::Cobbler.new(engine_attrs)
      rescue => e
        Astute.logger.error("Error occured during cobbler initializing")
        reporter.report({
                          'status' => 'error',
                          'error' => 'Cobbler can not be initialized',
                          'progress' => 100
                        })
        raise e
      end
    end

    def add_nodes_to_cobbler(engine, nodes)
      nodes.each do |node|
        begin
          Astute.logger.info("Adding #{node['name']} into cobbler")
          engine.item_from_hash('system', node['name'], node,
                           :item_preremove => true)
        rescue RuntimeError => e
          Astute.logger.error("Error occured while adding system #{node['name']} to cobbler")
          raise e
        end
      end # end iteration
    end
        
    def reboot_nodes(engine, nodes)
      nodes.inject({}) do |reboot_events, node|
        Astute.logger.debug("Trying to reboot node: #{node['name']}")
        reboot_events.merge(node['name'] => engine.power_reboot(node['name']))
      end
    end

    def check_reboot_nodes(engine, reboot_events)
      begin
        Astute.logger.debug("Waiting for reboot to be complete: nodes: #{reboot_events.keys}")
        failed_nodes = []
        Timeout::timeout(Astute.config.REBOOT_TIMEOUT) do
          while not reboot_events.empty?
            reboot_events.each do |node_name, event_id|
              event_status = engine.event_status(event_id)
              Astute.logger.debug("Reboot task status: node: #{node_name} status: #{event_status}")
              if event_status[2] =~ /^failed$/
                Astute.logger.error("Error occured while trying to reboot: #{node_name}")
                reboot_events.delete(node_name)
                failed_nodes << node_name
              elsif event_status[2] =~ /^complete$/
                Astute.logger.debug("Successfully rebooted: #{node_name}")
                reboot_events.delete(node_name)
              end
            end
            sleep(5)
          end
        end
      rescue Timeout::Error => e
        Astute.logger.debug("Reboot timeout: reboot tasks not completed for nodes #{reboot_events.keys}")
        raise e
      end
      failed_nodes
    end

    def report_about_progress(reporter, provisionLogParser, nodes_uids, target_uids, nodes)
      begin
        nodes_progress = provisionLogParser.progress_calculate(nodes_uids, nodes)
        nodes_progress.each do |n|
          if target_uids.include?(n['uid'])
            n['progress'] = 100
            n['status']   = 'provisioned'
          else
            n['status']   = 'provisioning'
          end
        end
        reporter.report({'nodes' => nodes_progress})
      rescue => e
        Astute.logger.warn "Some error occurred when parse logs for nodes progress: #{e.message}, trace: #{e.format_backtrace}"
      end
    end
    
    private
    
    def validate_provision_attrs(engine_attrs, nodes, do_raise = true)
      Validator.new(:provision).validate_data({'engine' => engine_attrs, 'nodes' => nodes}, do_raise)
    end
    
  end
end

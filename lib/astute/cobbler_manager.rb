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
  class CobblerManager
    def initialize(engine_attrs, reporter)
      raise "Settings for Cobbler must be set" if engine_attrs.blank?

      begin
        Astute.logger.info("Trying to instantiate cobbler engine: #{engine_attrs.inspect}")
        @engine = Astute::Provision::Cobbler.new(engine_attrs)
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

    def add_nodes(nodes)
      nodes.each do |node|
        cobbler_name = node['slave_name']
        begin
          Astute.logger.info("Adding #{cobbler_name} into cobbler")
          if node.fetch('ks_meta',{})['repo_metadata']
             converted_metadata = node['ks_meta']['repo_metadata'].map { |k,v| "#{k}=#{v}"}.join(',')
             node['ks_meta']['repo_metadata'] = converted_metadata
          end
          @engine.item_from_hash('system', cobbler_name, node, :item_preremove => true)
        rescue RuntimeError => e
          Astute.logger.error("Error occured while adding system #{cobbler_name} to cobbler")
          raise e
        end
      end
    ensure
      sync
    end

    def remove_nodes(nodes)
      nodes.each do |node|
        cobbler_name = node['slave_name']
        if @engine.system_exists?(cobbler_name)
          Astute.logger.info("Removing system from cobbler: #{cobbler_name}")
          @engine.remove_system(cobbler_name)
          if !@engine.system_exists?(cobbler_name)
            Astute.logger.info("System has been successfully removed from cobbler: #{cobbler_name}")
          else
            Astute.logger.error("Cannot remove node from cobbler: #{cobbler_name}")
          end
        else
          Astute.logger.info("System is not in cobbler: #{cobbler_name}")
        end
      end
    ensure
      sync
    end

    def reboot_nodes(nodes)
      nodes.inject({}) do |reboot_events, node|
        cobbler_name = node['slave_name']
        Astute.logger.debug("Trying to reboot node: #{cobbler_name}")
        reboot_events.merge(cobbler_name => @engine.power_reboot(cobbler_name))
      end
    ensure
      sync
    end

    def check_reboot_nodes(reboot_events)
      begin
        Astute.logger.debug("Waiting for reboot to be complete: nodes: #{reboot_events.keys}")
        failed_nodes = []
        Timeout::timeout(Astute.config.REBOOT_TIMEOUT) do
          while not reboot_events.empty?
            reboot_events.each do |node_name, event_id|
              event_status = @engine.event_status(event_id)
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

    def sync
      Astute.logger.debug("Cobbler syncing")
      @engine.sync
    end

  end
end
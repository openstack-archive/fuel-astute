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
          @engine.item_from_hash('system', cobbler_name, node, :item_preremove => true)
        rescue RuntimeError => e
          Astute.logger.error("Error occured while adding system #{cobbler_name} to cobbler")
          raise e
        end
      end
    ensure
      sync
    end

    def remove_nodes(nodes, retries=3, interval=2)
      nodes_to_remove = nodes.map {|node| node['slave_name']}.uniq
      Astute.logger.info("Total list of nodes to remove: #{nodes_to_remove.pretty_inspect}")
      retries.times do
        nodes_to_remove.map! do |name|
          if @engine.system_exists?(name)
            Astute.logger.info("Trying to remove system from cobbler: #{name}")
            @engine.remove_system(name)
            name if @engine.system_exists?(name)
          else
            Astute.logger.info("System is not in cobbler: #{name}")
          end
        end
        return if nodes_to_remove.empty?
        sleep(interval) if interval > 0
      end
    ensure
      Astute.logger.error("Cannot remove nodes from cobbler: #{nodes_to_remove.pretty_inspect}") if nodes_to_remove.present?
      sync
    end

    def reboot_nodes(nodes)
      splay = calculate_splay_between_nodes(nodes)
      nodes.inject({}) do |reboot_events, node|
        cobbler_name = node['slave_name']
        Astute.logger.debug("Trying to reboot node: #{cobbler_name}")

        #Sleep up to splay seconds before reboot for load balancing
        sleep splay
        reboot_events.merge(cobbler_name => @engine.power_reboot(cobbler_name))
      end
    end

    def check_reboot_nodes(reboot_events)
      begin
        Astute.logger.debug("Waiting for reboot to be complete: nodes: #{reboot_events.keys}")
        failed_nodes = []
        Timeout::timeout(Astute.config.reboot_timeout) do
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

    def edit_nodes(nodes, data)
      nodes.each do |node|
        cobbler_name = node['slave_name']
        begin
          Astute.logger.info("Changing cobbler system #{cobbler_name}")
          @engine.item_from_hash('system', cobbler_name, data, :item_preremove => false)
        rescue RuntimeError => e
          Astute.logger.error("Error occured while changing cobbler system #{cobbler_name}")
          raise e
        end
      end
    ensure
      sync
    end

    def netboot_nodes(nodes, state)
      nodes.each do |node|
        cobbler_name = node['slave_name']
        begin
          Astute.logger.info("Changing node netboot state #{cobbler_name}")
          @engine.netboot(cobbler_name, state)
        rescue RuntimeError => e
          Astute.logger.error("Error while changing node netboot state #{cobbler_name}")
          raise e
        end
      end
    ensure
      sync
    end

    def get_existent_nodes(nodes)
      existent_nodes = []
      nodes.each do |node|
        cobbler_name = node['slave_name']
        if @engine.system_exists?(cobbler_name)
          Astute.logger.info("Update #{cobbler_name}, node already exists in cobbler")
          existent_nodes << node
        end
      end
      existent_nodes
    end

    def get_mac_duplicate_names(nodes)
      mac_duplicate_names = []
      nodes.each do |node|
        Astute.logger.info("Trying to find MAC duplicates for node #{node['slave_name']}")
        if node['interfaces']
          node['interfaces'].each do |iname, ihash|
            if ihash['mac_address']
              Astute.logger.info("Trying to find system with MAC: #{ihash['mac_address']}")
              found_node = @engine.system_by_mac(ihash['mac_address'])
              mac_duplicate_names << found_node['name'] if found_node
            end
          end
        end
      end
      mac_duplicate_names.uniq
    end

    def sync
      Astute.logger.debug("Cobbler syncing")
      @engine.sync
    end

    private

    def calculate_splay_between_nodes(nodes)
      # For 20 nodes, 120 iops and 180 splay_factor splay will be 1.5749
      (nodes.size + 1)  / Astute.config.iops.to_f * Astute.config.splay_factor / nodes.size
    end

  end
end

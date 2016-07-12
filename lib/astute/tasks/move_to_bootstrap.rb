#    Copyright 2016 Mirantis, Inc.
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
  class MoveToBootstrap < Task

    def initialize(task, context)
      super
      @work_thread = nil
    end

    private

    def process
      cobbler = CobblerManager.new(
        @task['parameters']['provisioning_info']['engine'],
        @ctx.reporter
      )

      @work_thread = Thread.new do
        is_exist = cobbler.get_existent_nodes(
          @task['parameters']['provisioning_info']['nodes']
        ).present?

        # Change node type to prevent wrong node detection as provisioned
        # Also this type if node will not rebooted, Astute will be allowed
        # to try to reboot such nodes again
        change_nodes_type('reprovisioned') if is_exist
        cobbler.edit_nodes(@task['parameters']['provisioning_info']['nodes'],
                           {'profile' => Astute.config.bootstrap_profile})
        cobbler.netboot_nodes(@task['parameters']['provisioning_info']['nodes'],
                              true)

        Reboot.new('node_id' => @task['node_id']) if is_exist
        Rsyslogd.send_sighup(
          @ctx,
          @task['parameters']['provisioning_info']['engine']["master_ip"]
        )

        cobbler.remove_nodes(nodes)
        # NOTE(kozhukalov): We try to find out if there are systems
        # in the Cobbler with the same MAC addresses. If so, Cobbler is going
        # to throw MAC address duplication error. We need to remove these
        # nodes.
        mac_duplicate_names = cobbler.get_mac_duplicate_names(nodes)
        if mac_duplicate_names.present?
          cobbler.remove_nodes(mac_duplicate_names.map {|n| {'slave_name' => n}})
        end

        cobbler.add_nodes(nodes)
      end
    end

    def calculate_status
      @work_thread.join and succeed! unless @work_thread.alive?
    end

    def validation
      validate_presence(@task['parameters'], 'provisioning_info')
      validate_presence(@task, 'node_id')
    end

    def change_nodes_type(type="image")
      run_shell_without_check(
        @task['node_id'],
        "echo '#{type}' > /etc/nailgun_systemtype",
        _timeout=5
      )[:stdout]
    rescue Astute::MClientTimeout, Astute::MClientError => e
      Astute.logger.debug("#{@ctx.task_id}: #{task_name} mcollective " \
        "change type command failed with error #{e.message}")
      nil
    end

  end
end
#    Copyright 2015 Mirantis, Inc.
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
  class Reboot < Task

    private

    def process
      @control_time = boot_time
      failed! and return if boot_time == 0

      @time_start = Time.now.to_i
      @already_rebooted = false

      reboot
    end

    def calculate_status
      if Time.now.to_i - @time_start > @task['parameters']['timeout']
        failed! and return
      end

      current_bt = boot_time
      succeed! if current_bt != @control_time && current_bt != 0
    end

    def pre_validation
      validate_presence(@task, 'node_id')
    end

    def setup_default
      @task['parameters']['timeout'] ||= 300
    end

    def reboot
      run_shell_without_check(
        Array(@task['node_id']),
        'reboot',
        timeout=2
      )
    rescue Astute::MClientTimeout, Astute::MClientError => e
      failed!
    end

    def boot_time
      run_shell_without_check(
        Array(@task['node_id']),
        "stat --printf='%Y' /proc/1",
        timeout=2
      )[:stdout].to_i
    rescue Astute::MClientTimeout, Astute::MClientError => e
      0
    end

  end
end
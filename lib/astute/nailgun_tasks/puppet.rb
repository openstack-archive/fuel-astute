#    Copyright 2014 Mirantis, Inc.
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

require 'timeout'

module Astute
  class Puppet < NailgunTask

    private

    def process
      @puppet_task = run_puppet
    end

    def calculate_status
      case @puppet_task.status
      when 'ready' then succeed!
      when 'error' then failed!
      end
    end

    def pre_validation
      validate_presence(@hook, 'uids')
      validate_presence(@hook['parameters'], 'puppet_manifest')
      validate_presence(@hook['parameters'], 'puppet_modules')
      validate_presence(@hook['parameters'], 'cwd')
    end

    def setup_default
      @hook['parameters']['timeout'] ||= 300
      @hook['parameters']['retries'] ||= Astute.config.puppet_retries
      @hook['parameters']['debug'] = false unless @hook['parameters']['debug'].present?
    end

    def run_puppet
      PuppetTask.new(
        @ctx,
        {'uid' => @hook['uids'].first.to_s, 'role' => task_name},
        @hook['parameters']['retries'],
        @hook['parameters']['puppet_manifest'],
        @hook['parameters']['puppet_modules'],
        @hook['parameters']['cwd'],
        @hook['parameters']['timeout'],
        @hook['parameters']['debug']
      )
    end

  end # class
end
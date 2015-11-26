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
  class UploadFiles < NailgunTask

    private

    def process
      @work_thread = Thread.new do
        hook['parameters']['nodes'].each do |node|
          node['files'].each do |file|
            parameters = {
              'content' => file['data'],
              'path' => file['dst'],
              'permissions' => file['permissions'] || '0644',
              'dir_permissions' => file['dir_permissions'] || '0755',
            }
            @nodes_status[node['uid']] = upload_file(node['uid'], parameters)
          end
        end
      end
    end

    def calculate_status
      failed! and return if @nodes_status.values.include?(false)
      succeed! and return if @nodes_status.all?{ |s| s == true }

      unless !@work_thread.alive?
        @nodes_status.each { |k, v| @nodes_status[k] = false if v == :pending }
      end
    end

    def pre_validation
      validate_presence(@hook['parameters'], 'nodes')
    end

    def setup_default
      @nodes_status = @hook['parameters']['nodes'].inject({}) do |n_s, n|
        n_s.merge({ n['uid'] => :pending })
      end
    end

  end
end
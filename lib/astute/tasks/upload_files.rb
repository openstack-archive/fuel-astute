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
  class UploadFiles < Task

    def post_initialize(task, context)
      @nodes_status = task['parameters']['nodes'].inject({}) do |n_s, n|
        n_s.merge({ n['uid'] => :pending })
      end
    end

    private

    def process
      task['parameters']['nodes'].each do |node|
        node['files'].each do |file|
          parameters = {
            'content' => file['data'],
            'path' => file['dst'],
            'permissions' => file['permissions'] || '0644',
            'dir_permissions' => file['dir_permissions'] || '0755',
          }
          if @nodes_status[node['uid']]
            @nodes_status[node['uid']] = upload_file_with_check(node['uid'], parameters)
          end
        end
      end
    end

    def calculate_status
      if @nodes_status.values.all? { |v| v != :pending }
        failed! if @nodes_status.values.include?(false)
        succeed! if @nodes_status.values.all?{ |s| s == true }
        return
      end
    end

    def validation
      validate_presence(task['parameters'], 'nodes')
    end

  end
end
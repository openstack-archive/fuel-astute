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
  class CopyFiles < Task

    def initialize(task, context)
      super
      @work_thread = nil
      @files_status = @task['parameters']['files'].inject({}) do |f_s, n|
        f_s.merge({ n['src']+n['dst'] => :pending })
      end
    end

    private

    def process
      @task['parameters']['files'].each do |file|
        if File.file?(file['src']) && File.readable?(file['src'])
          parameters = {
            'content' => File.binread(file['src']),
            'path' => file['dst'],
            'permissions' => file['permissions'] || @task['parameters']['permissions'],
            'dir_permissions' => file['dir_permissions'] || @task['parameters']['dir_permissions'],
          }
          @files_status[file['src']+file['dst']] =
            upload_file(@task['node_id'], parameters)
        else
          @files_status[file['src']+file['dst']] = false
        end
      end # files
    end

    def calculate_status
      if @files_status.values.all?{ |s| s != :pending }
        failed! if @files_status.values.include?(false)
        succeed! if @files_status.values.all?{ |s| s == true }
        return
      end
    end

    def validation
      validate_presence(@task, 'node_id')
      validate_presence(@task['parameters'], 'files')
    end

  end
end
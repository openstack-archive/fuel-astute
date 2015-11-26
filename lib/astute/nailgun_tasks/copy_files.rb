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
  class CopyFiles < NailgunTask

    private

    def process
      @work_thread = Thread.new do
        @hook['parameters']['files'].each do |file|
          if File.file?(file['src']) && File.readable?(file['src'])
            parameters = {
              'content' => File.binread(file['src']),
              'path' => file['dst'],
              'permissions' => file['permissions'] || @hook['parameters']['permissions'],
              'dir_permissions' => file['dir_permissions'] || @hook['parameters']['dir_permissions'],
            }
            @files_status[file['src']] = upload_file(@hook['uids'], parameters)
          else
            @files_status[file['src']] = false
          end
        end

      end
    end

    def calculate_status
      failed! and return if @files_status.values.include?(false)
      succeed! and return if @files_status.all?{ |s| s == true }

      unless !@work_thread.alive?
        @files_status.each { |k, v| @files_status[k] = false if v == :pending }
      end
    end

    def pre_validation
      validate_presence(@hook, 'uids')
      validate_presence(@hook['parameters'], 'files')
    end

    def setup_default
      @files_status = @hook['parameters']['files'].inject({}) do |f_s, n|
        f_s.merge({ n['src'] => :pending })
      end
    end

  end
end
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
  class UploadFile < Task

    def initialize(task, context)
      super
      @upload_status = :pending
    end

    private

    def process
      @upload_status = upload_file(@task['node_id'], @task['parameters'])
    end

    def calculate_status
      if [true, false].include? @upload_status
        @upload_status ? succeed! : failed!
        return
      end
    end

    def validation
      validate_presence(@task, 'node_id')
      validate_presence(@task['parameters'], 'path')
      validate_presence(@task['parameters'], 'data')
    end

    def setup_default
      @task['parameters']['content'] = @task['parameters']['data']
      @task['parameters']['timeout'] ||= Astute.config.upload_timeout
    end

  end
end

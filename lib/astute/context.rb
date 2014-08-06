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
  class Context
    attr_accessor :reporter, :deploy_log_parser
    attr_reader   :task_id, :status

    def initialize(task_id, reporter, deploy_log_parser=nil)
      @task_id = task_id
      @reporter = reporter
      @status = {}
      @deploy_log_parser = deploy_log_parser
    end

    def report_and_update_status(data)
      if data['nodes']
        data['nodes'].each do |node|
          #TODO(vsharshov): save node role to hash
          @status.merge! node['uid'] => node['status'] if node['uid'] && node['status']
        end
      end
      reporter.report(data)
    end

  end
end

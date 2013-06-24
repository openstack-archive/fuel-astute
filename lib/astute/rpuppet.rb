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


require 'json'
require 'timeout'

module Astute
  module RpuppetDeployer
    def self.rpuppet_deploy(ctx, nodes, parameters, classes, env="production")
      if nodes.empty?
        Astute.logger.info "#{ctx.task_id}: Nodes to deploy are not provided. Do nothing."
        return false
      end
      uids = nodes.map {|n| n['uid']}
      data = {
        "parameters" => parameters,
        "classes" => classes,
        "environment" => env
      }
      Astute.logger.debug "Waiting for puppet to finish deployment on all nodes (timeout = #{Astute.config.PUPPET_TIMEOUT} sec)..."
      time_before = Time.now
      Timeout::timeout(Astute.config.PUPPET_TIMEOUT) do
        rpuppet = MClient.new(ctx, "rpuppet", uids)
        rpuppet.run(:data => data.to_json)
      end
      time_spent = Time.now - time_before
      Astute.logger.info "#{ctx.task_id}: Spent #{time_spent} seconds on puppet run for following nodes(uids): #{nodes.map {|n| n['uid']}.join(',')}"
    end
  end
end

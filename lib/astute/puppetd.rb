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
  module PuppetdDeployer

    def self.deploy(ctx, nodes, retries=2, puppet_manifest=nil, puppet_modules=nil, cwd=nil)
      @ctx = ctx
      @retries = retries
      @nodes = nodes
      @puppet_manifest = puppet_manifest || '/etc/puppet/manifests/site.pp'
      @puppet_modules = puppet_modules || '/etc/puppet/modules'
      @cwd = cwd || '/'

      Astute.logger.debug "Waiting for puppet to finish deployment on all
                           nodes (timeout = #{Astute.config.PUPPET_TIMEOUT} sec)..."
      time_before = Time.now

      deploy_nodes

      time_spent = Time.now - time_before
      Astute.logger.info "#{@ctx.task_id}: Spent #{time_spent} seconds on puppet run "\
                         "for following nodes(uids): #{@nodes.map {|n| n['uid']}.join(',')}"
    end

    private

    def self.deploy_nodes
      puppet_tasks = @nodes.map { |n| puppet_task(n) }
      puppet_tasks.each(&:run)

      while puppet_tasks.any? { |t| t.status == 'deploying' }
        sleep Astute.config.PUPPET_DEPLOY_INTERVAL
      end
    end

    def self.puppet_task(n)
      PuppetTask.new(@ctx, n, @retries, @puppet_manifest, @puppet_modules, @cwd)
    end

  end
end

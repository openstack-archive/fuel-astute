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
  class DeploymentEngine

    def initialize(context)
      if self.class.superclass.name == 'Object'
        raise "Instantiation of this superclass is not allowed. Please subclass from #{self.class.name}."
      end
      @ctx = context
    end

    def deploy(deployment_info)
      # FIXME (eli): need to get rid all deployment_mode ifs from orchetrator
      deployment_mode = deployment_info[0]['deployment_mode']

      @ctx.deploy_log_parser.deploy_type = deployment_mode
      self.send("deploy_#{deployment_mode}", deployment_info)
    end

    def method_missing(method, *args)
      Astute.logger.error "Method #{method} is not implemented for #{self.class}, raising exception."
      raise "Method #{method} is not implemented for #{self.class}"
    end

    # This method is called by Ruby metaprogramming magic from deploy method
    # It should not contain any magic with attributes, and should not directly run any type of MC plugins
    # It does only support of deployment sequence. See deploy_piece implementation in subclasses.
    def deploy_multinode(nodes)
      ctrl_nodes = nodes.select {|n| n['role'] == 'controller'}
      other_nodes = nodes - ctrl_nodes

      Astute.logger.info "Starting deployment of primary controller"
      deploy_piece(ctrl_nodes)

      Astute.logger.info "Starting deployment of other nodes"
      deploy_piece(other_nodes)

      nil
    end

    def deploy_ha_full(nodes)
      primary_ctrl_nodes = nodes.select {|n| n['role'] == 'primary-controller'}
      ctrl_nodes = nodes.select {|n| n['role'] == 'controller'}
      compute_nodes = nodes.select {|n| n['role'] == 'compute'}
      quantum_nodes = nodes.select {|n| n['role'] == 'quantum'}
      storage_nodes = nodes.select {|n| n['role'] == 'storage'}
      proxy_nodes = nodes.select {|n| n['role'] == 'swift-proxy'}
      primary_proxy_nodes = nodes.select {|n| n['role'] == 'primary-swift-proxy'}
      other_nodes = nodes - ctrl_nodes - primary_ctrl_nodes - \
        primary_proxy_nodes - quantum_nodes - storage_nodes - proxy_nodes

      Astute.logger.info "Starting deployment of primary swift proxy"
      deploy_piece(primary_proxy_nodes)

      Astute.logger.info "Starting deployment of non-primary swift proxies"
      deploy_piece(proxy_nodes)

      Astute.logger.info "Starting deployment of swift storages"
      deploy_piece(storage_nodes)

      Astute.logger.info "Starting deployment of primary controller"
      deploy_piece(primary_ctrl_nodes)

      Astute.logger.info "Starting deployment of all controllers one by one"
      ctrl_nodes.each {|n| deploy_piece([n])}

      Astute.logger.info "Starting deployment of other nodes"
      deploy_piece(other_nodes)

      nil
    end

    def deploy_ha_compact(nodes)
      primary_ctrl_nodes = nodes.select {|n| n['role'] == 'primary-controller'}
      ctrl_nodes = nodes.select {|n| n['role'] == 'controller'}
      compute_nodes = nodes.select {|n| n['role'] == 'compute'}
      quantum_nodes = nodes.select {|n| n['role'] == 'quantum'}
      storage_nodes = nodes.select {|n| n['role'] == 'storage'}
      proxy_nodes = nodes.select {|n| n['role'] == 'swift-proxy'}
      primary_proxy_nodes = nodes.select {|n| n['role'] == 'primary-swift-proxy'}
      other_nodes = nodes - ctrl_nodes - primary_ctrl_nodes - \
        primary_proxy_nodes - quantum_nodes

      Astute.logger.info "Starting deployment of primary controller"
      deploy_piece(primary_ctrl_nodes)

      Astute.logger.info "Starting deployment of all controllers one by one"
      ctrl_nodes.each {|n| deploy_piece([n])}

      Astute.logger.info "Starting deployment of other nodes"
      deploy_piece(other_nodes)

      nil
    end

    def validate_nodes(nodes)
      if nodes.empty?
        Astute.logger.info "#{@ctx.task_id}: Nodes to deploy are not provided. Do nothing."
        return false
      end
      return true
    end

    def nodes_status(nodes, status, data_to_merge)
      {'nodes' => nodes.map { |n| {'uid' => n['uid'], 'status' => status}.merge(data_to_merge) }}
    end

  end
end

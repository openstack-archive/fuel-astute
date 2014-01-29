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


require 'mcollective'
require 'timeout'

module Astute

  class MClientTimeout < Timeout::Error; end

  class MClient
    include MCollective::RPC

    attr_accessor :retries

    def initialize(ctx, agent, nodes=nil, check_result=true, timeout=nil, retries=Astute.config.MC_RETRIES)
      @task_id = ctx.task_id
      @agent = agent
      @nodes = nodes.map { |n| n.to_s } if nodes
      @check_result = check_result
      # Will be used a minimum of two things: the specified parameter(timeout)
      # and timeout from DDL (10 sec by default if not explicitly specified in DDL)
      # If timeout here is nil will be used value from DDL.
      # Examples:
      # timeout - 10 sec, DDL - 20 sec. Result — 10 sec.
      # timeout - 30 sec, DDL - 20 sec. Result — 20 sec.
      # timeout - 20 sec, DDL - not set. Result — 10 sec.
      @timeout = timeout
      @retries = retries
      initialize_mclient
    end

    def on_respond_timeout(&block)
      @on_respond_timeout = block
      self
    end

    def method_missing(method, *args)
      @mc_res = mc_send(method, *args)

      if method == :discover
        @nodes = args[0][:nodes]
        return @mc_res
      end

      # Enable if needed. In normal case it eats the screen pretty fast
      log_result(@mc_res, method)

      check_results_with_retries(method, args) if @check_result

      @mc_res
    end

  private

    def check_results_with_retries(method, args)
      err_msg = ''
      timeout_nodes_count = 0
      # Following error might happen because of misconfiguration, ex. direct_addressing = 1 only on client
      #  or.. could be just some hang? Let's retry if @retries is set
      if @mc_res.length < @nodes.length
        # some nodes didn't respond
        retry_index = 1
        while retry_index <= @retries
          sleep rand
          nodes_responded = @mc_res.map { |n| n.results[:sender] }
          not_responded = @nodes - nodes_responded
          Astute.logger.debug "Retry ##{retry_index} to run mcollective agent on nodes: '#{not_responded.join(',')}'"
          mc_send :discover, :nodes => not_responded
          @new_res = mc_send(method, *args)
          log_result(@new_res, method)
          # @new_res can have some nodes which finally responded
          @mc_res += @new_res
          break if @mc_res.length == @nodes.length
          retry_index += 1
        end
        if @mc_res.length < @nodes.length
          nodes_responded = @mc_res.map { |n| n.results[:sender] }
          not_responded = @nodes - nodes_responded
          if @on_respond_timeout
            @on_respond_timeout.call not_responded
          else
            err_msg += "MCollective agents '#{not_responded.join(',')}' didn't respond within the allotted time.\n"
            timeout_nodes_count += not_responded.size
          end
        end
      end
      failed = @mc_res.select { |x| x.results[:statuscode] != 0 }
      if failed.any?
        err_msg += "MCollective call failed in agent '#{@agent}', "\
                     "method '#{method}', failed nodes: \n"
        failed.each do |n|
          err_msg += "ID: #{n.results[:sender]} - Reason: #{n.results[:statusmsg]}\n"
        end
      end
      if err_msg.present?
        Astute.logger.error err_msg
        expired_size = failed.count { |n| n.results[:statusmsg] == 'execution expired' }
        # Detect TimeOut: 1 condition - fail because of DDL timeout, 2 - fail because of custom timeout
        if (failed.present? && failed.size == expired_size) || (timeout_nodes_count > 0 && failed.empty?)
          raise MClientTimeout, "#{@task_id}: #{err_msg}"
        else
          raise MClientError, "#{@task_id}: #{err_msg}"
        end
      end
    end

    def mc_send(*args)
      @mc.send(*args)
    rescue => ex
      case ex
      when Stomp::Error::NoCurrentConnection
        # stupid stomp cannot recover severed connection
        stomp = MCollective::PluginManager["connector_plugin"]
        stomp.disconnect rescue nil
        stomp.instance_variable_set :@connection, nil
        initialize_mclient
      end
      sleep rand
      Astute.logger.error "Retrying MCollective call after exception: #{ex}"
      retry
    end

    def initialize_mclient
      @mc = rpcclient(@agent, :exit_on_failure => false)
      @mc.timeout = @timeout if @timeout
      @mc.progress = false
      if @nodes
        @mc.discover :nodes => @nodes
      end
    rescue => ex
      Astute.logger.error "Retrying RPC client instantiation after exception: #{ex}"
      sleep 5
      retry
    end

    def log_result(result, method)
      result.each do |node|
        Astute.logger.debug "#{@task_id}: MC agent '#{node.agent}', method '#{method}', "\
                            "results: #{node.results.inspect}"
      end
    end
  end
end

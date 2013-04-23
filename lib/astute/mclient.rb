require 'mcollective'

module Astute
  class MClient
    include MCollective::RPC

    attr_accessor :retries

    def initialize(ctx, agent, nodes=nil, check_result=true, timeout=nil)
      @task_id = ctx.task_id
      @agent = agent
      @nodes = nodes.map { |n| n.to_s } if nodes
      @check_result = check_result
      @retries = Astute.config.MC_RETRIES
      @timeout = timeout
      initialize_mclient
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
          err_msg += "MCollective agents '#{not_responded.join(',')}' didn't respond. \n"
        end
      end
      failed = @mc_res.select{|x| x.results[:statuscode] != 0 }
      if failed.any?
        err_msg += "MCollective call failed in agent '#{@agent}', "\
                     "method '#{method}', failed nodes: #{failed.map{|x| x.results[:sender]}.join(',')} \n"
      end
      unless err_msg.empty?
        Astute.logger.error err_msg
        raise "#{@task_id}: #{err_msg}"
      end
    end


    def mc_send(*args)
      @mc.send(*args)
    rescue => ex
      Astute.logger.error "Retrying MCollective call after exception: #{ex}"
      initialize_mclient
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

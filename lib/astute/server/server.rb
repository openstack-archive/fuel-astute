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
require 'securerandom'
require 'astute/server/task_queue'
require 'zlib'

module Astute
  module Server

    class Server
      def initialize(channels_and_exchanges, delegate, producer)
        @channel  = channels_and_exchanges[:channel]
        @exchange = channels_and_exchanges[:exchange]
        @delegate = delegate
        @producer = producer
        @service_channel = channels_and_exchanges[:service_channel]
        @service_exchange = channels_and_exchanges[:service_exchange]
        # NOTE(eli): Generate unique name for service queue
        # See bug: https://bugs.launchpad.net/fuel/+bug/1485895
        @service_queue_name = "naily_service_#{SecureRandom.uuid}"
        @watch_thread = nil
      end

      def run
        @queue = @channel.queue(
          Astute.config.broker_queue,
          :durable => true
        )
        @queue.bind(@exchange)

        @service_queue = @service_channel.queue(
          @service_queue_name,
          :exclusive => true,
          :auto_delete => true
        )
        @service_queue.bind(@service_exchange)

        @main_work_thread = nil
        @tasks_queue = TaskQueue.new

        register_callbacks

        run_infinite_loop
        @watch_thread.join
      end

      def stop
        @watch_thread.wakeup
      end

    private

      def run_infinite_loop
        @watch_thread = Thread.new do
          Thread.stop
          Astute.logger.debug "Stop main thread"
        end
      end

      def register_callbacks
        main_worker
        service_worker
      end

      def main_worker
        @queue.subscribe(:manual_ack => true) do |delivery_info, properties, payload|
          if @main_work_thread.nil? || !@main_work_thread.alive?
            @channel.acknowledge(delivery_info.delivery_tag, false)
            perform_main_job(payload, properties)
          else
            Astute.logger.debug "Requeue message because worker is busy"
            # Avoid throttle by consume/reject cycle
            # if only one worker is running
            @channel.reject(delivery_info.delivery_tag, true)
          end
        end
      end

      def service_worker
        @service_queue.subscribe do |_delivery_info, properties, payload|
          perform_service_job(payload, properties)
        end
      end

      def send_message_task_in_orchestrator(data)
        data.each do |message|
          begin
            task_uuid = message['args']['task_uuid']
            Astute.logger.debug "Sending message: task #{task_uuid} in orchestrator"
            return_results({
              'respond_to' => 'task_in_orchestrator',
              'args' => {'task_uuid' => task_uuid}})
          rescue => ex
            Astute.logger.error "Error on sending message 'task in orchestrator': #{ex.message}"
          end
        end
      end

      def perform_main_job(payload, properties)
        @main_work_thread = Thread.new do
          data = parse_data(payload, properties)
          Astute.logger.debug("Process message from worker queue:\n"\
            "#{data.pretty_inspect}")
          @tasks_queue = Astute::Server::TaskQueue.new

          @tasks_queue.add_task(data)
          send_message_task_in_orchestrator(data)
          dispatch(@tasks_queue)

          # Clean up tasks queue to prevent wrong service job work flow for
          # already finished tasks
          @tasks_queue = TaskQueue.new
        end
      end

      def perform_service_job(payload, properties)
        Thread.new do
          service_data = {
            :main_work_thread => @main_work_thread,
            :tasks_queue => @tasks_queue
          }
          data = parse_data(payload, properties)
          Astute.logger.debug("Process message from service queue:\n"\
            "#{data.pretty_inspect}")
          send_message_task_in_orchestrator(data)
          dispatch(data, service_data)
        end
      end

      def dispatch(data, service_data=nil)
        data.each_with_index do |message, i|
          begin
            dispatch_message message, service_data
          rescue StopIteration
            Astute.logger.debug "Dispatching aborted by #{message['method']}"
            abort_messages data[(i + 1)..-1]
            break
          rescue => ex
            Astute.logger.error "Error running RPC method "\
                                "#{message['method']}: #{ex.message}, "\
                                "trace: #{ex.format_backtrace}"
            return_results message, {
              'status' => 'error',
              'error'  => "Method #{message['method']}. #{ex.message}.\n" \
                          "Inspect Astute logs for the details"
            }
            break
          end
        end
      end

      def dispatch_message(data, service_data=nil)
        if Astute.config.fake_dispatch
          Astute.logger.debug "Fake dispatch"
          return
        end

        unless @delegate.respond_to?(data['method'])
          Astute.logger.error "Unsupported RPC call '#{data['method']}'"
          return_results data, {
            'status' => 'error',
            'error'  => "Unsupported method '#{data['method']}' called."
          }
          return
        end

        if service_data.nil?
          Astute.logger.debug "Main worker task id is "\
                              "#{@tasks_queue.current_task_id}"
        end

        Astute.logger.info "Processing RPC call '#{data['method']}'"
        if !service_data
          @delegate.send(data['method'], data)
        else
          @delegate.send(data['method'], data, service_data)
        end
      end

      def return_results(message, results={})
        if results.is_a?(Hash) && message['respond_to']
          reporter = Astute::Server::Reporter.new(
            @producer,
            message['respond_to'],
            message['args']['task_uuid']
          )
          reporter.report results
        end
      end

      def parse_data(data, properties)
        data = unzip_message(data, properties) if zip?(properties)
        messages = begin
          JSON.load(data)
        rescue => e
          Astute.logger.error "Error deserializing payload: #{e.message},"\
                              " trace:\n#{e.backtrace.pretty_inspect}"
          nil
        end
        messages.is_a?(Array) ? messages : [messages]
      end

      def unzip_message(data, properties)
        Zlib::Inflate.inflate(data)
      rescue => e
        msg = "Gzip failure with error #{e.message} in\n"\
          "#{e.backtrace.pretty_inspect} with properties\n"\
          "#{properties.pretty_inspect} on data\n#{data.pretty_inspect}"
        Astute.logger.error(msg)
        raise e, msg
      end

      def zip?(properties)
        properties[:headers]['compression'] == "application/x-gzip"
      end

      def abort_messages(messages)
        return unless messages && messages.size > 0
        messages.each do |message|
          begin
            Astute.logger.debug "Aborting '#{message['method']}'"
            err_msg = {
              'status' => 'error',
              'error' => 'Task aborted',
              'progress' => 100
            }

            if message['args']['nodes'].instance_of?(Array)
              err_nodes = message['args']['nodes'].map do |node|
                {
                  'uid' => node['uid'],
                  'status' => 'error',
                  'error_type' => 'provision',
                  'progress' => 0
                }
              end

              err_msg.merge!('nodes' => err_nodes)
            end

            return_results(message, err_msg)
          rescue => ex
            Astute.logger.debug "Failed to abort '#{message['method']}':\n"\
                                "#{ex.pretty_inspect}"
          end
        end
      end
    end

  end #Server
end #Astute

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

require 'raemon'
require 'net/http'
require 'bunny'

module Astute
  module Server

    class Worker
      include Raemon::Worker

      DELAY_SEC = 5

      def start
        super
        start_heartbeat
        Astute::Server::AsyncLogger.start_up(Astute.logger)
        Astute.logger = Astute::Server::AsyncLogger
      end

      def stop
        super
        @connection.stop if defined?(@connection) && @connection.present?
        @producer.stop if defined?(@producer) && @producer.present?
        @server.stop if defined?(@server) && @server.present?
        Astute::Server::AsyncLogger.shutdown
      end

      def run
        Astute.logger.info "Worker initialization"
        run_server
      rescue Bunny::TCPConnectionFailed => e
        Astute.logger.warn "TCP connection to AMQP failed: #{e.message}. "\
                           "Retry #{DELAY_SEC} sec later..."
        sleep DELAY_SEC
        retry
      rescue Bunny::PossibleAuthenticationFailureError => e
        Astute.logger.warn "If problem repeated more than 5 minutes, "\
                           "please check "\
                           "authentication parameters. #{e.message}. "\
                           "Retry #{DELAY_SEC} sec later..."
        sleep DELAY_SEC
        retry
      rescue => e
        Astute.logger.error "Exception during worker initialization:"\
                            " #{e.message}, trace: #{e.format_backtrace}"
        Astute.logger.warn "Retry #{DELAY_SEC} sec later..."
        sleep DELAY_SEC
        retry
      end

      private

      def start_heartbeat
        @heartbeat ||= Thread.new do
          sleep 30
          heartbeat!
        end
      end

      def run_server
        @connection = Bunny.new(connection_options)
        @connection.start
        channels_and_exchanges = declare_channels_and_exchanges(@connection)

        @producer = Astute::Server::Producer.new(
          channels_and_exchanges[:report_exchange]
        )
        delegate = Astute::Server::Dispatcher.new(@producer)
        @server = Astute::Server::Server.new(
          channels_and_exchanges,
          delegate,
          @producer
        )

        @server.run
      end

      def declare_channels_and_exchanges(connection)
        # WARN: Bunny::Channel are designed to assume they are
        # not shared between threads.
        channel = @connection.create_channel
        exchange = channel.topic(
          Astute.config.broker_exchange,
          :durable => true
        )

        report_channel = @connection.create_channel
        report_exchange = report_channel.topic(
          Astute.config.broker_exchange,
          :durable => true
        )

        service_channel = @connection.create_channel
        service_channel.prefetch(0)

        service_exchange = service_channel.fanout(
          Astute.config.broker_service_exchange,
          :auto_delete => true
        )

        return {
          :exchange => exchange,
          :service_exchange => service_exchange,
          :channel => channel,
          :service_channel => service_channel,
          :report_channel => report_channel,
          :report_exchange => report_exchange
        }
      rescue Bunny::PreconditionFailed => e
        Astute.logger.warn "Try to remove problem exchanges and queues"
        if connection.queue_exists? Astute.config.broker_queue
          channel.queue_delete Astute.config.broker_queue
        end
        if connection.queue_exists? Astute.config.broker_publisher_queue
          channel.queue_delete Astute.config.broker_publisher_queue
        end

        cleanup_rabbitmq_stuff
        raise e
      end

      def connection_options
        {
          :host => Astute.config.broker_host,
          :port => Astute.config.broker_port,
          :user => Astute.config.broker_username,
          :pass => Astute.config.broker_password,
          :heartbeat => :server
        }.reject{|k, v| v.nil? }
      end

      def cleanup_rabbitmq_stuff
        Astute.logger.warn "Try to remove problem exchanges and queues"


        [Astute.config.broker_exchange,
         Astute.config.broker_service_exchange].each do |exchange|
          rest_delete("/api/exchanges/%2F/#{exchange}")
        end
      end

      def rest_delete(url)
        http = Net::HTTP.new(
          Astute.config.broker_host,
          Astute.config.broker_rest_api_port
        )
        request = Net::HTTP::Delete.new(url)
        request.basic_auth(
          Astute.config.broker_username,
          Astute.config.broker_password
        )

        response = http.request(request)

        case response.code.to_i
        when 204 then Astute.logger.debug "Successfully delete object at #{url}"
        when 404 then
        else
           Astute.logger.error "Failed to perform delete request. Debug"\
                               " information: http code: #{response.code},"\
                               " message: #{response.message},"\
                               " body #{response.body}"
        end
      end

    end # Worker
  end #Server
end #Astute

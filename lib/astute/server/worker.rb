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

module Astute
  module Server

    class Worker
      include Raemon::Worker

      DELAY_SEC = 5

      def start
        super
        start_heartbeat
      end

      def stop
        super
        begin
          @connection.close{ stop_event_machine } if @connection
        ensure
          stop_event_machine
        end
      end

      def run
        Astute.logger.info "Worker initialization"
        EM.run do
          run_server
        end
      rescue AMQP::TCPConnectionFailed => e
        Astute.logger.warn "TCP connection to AMQP failed: #{e.message}. Retry #{DELAY_SEC} sec later..."
        sleep DELAY_SEC
        retry
      rescue AMQP::PossibleAuthenticationFailureError => e
        Astute.logger.warn "If problem repeated more than 5 minutes, please check " \
                           "authentication parameters. #{e.message}. Retry #{DELAY_SEC} sec later..."
        sleep DELAY_SEC
        retry
      rescue => e
        Astute.logger.error "Exception during worker initialization: #{e.message}, trace: #{e.format_backtrace}"
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
        AMQP.logging = true
        AMQP.connect(connection_options) do |connection|
          @connection = configure_connection(connection)

          @channel = create_channel(@connection)
          @exchange = @channel.topic(Astute.config.broker_exchange, :durable => true)
          @service_channel = create_channel(@connection, prefetch=false)
          @service_exchange = @service_channel.fanout(Astute.config.broker_service_exchange, :auto_delete => true)

          @producer = Astute::Server::Producer.new(@exchange)
          @delegate = Astute.config.delegate || Astute::Server::Dispatcher.new(@producer)
          @server = Astute::Server::Server.new(@channel, @exchange, @delegate, @producer, @service_channel, @service_exchange)

          @server.run
        end
      end

      def configure_connection(connection)
        connection.on_tcp_connection_loss do |conn, settings|
          Astute.logger.warn "Trying to reconnect to message broker. Retry #{DELAY_SEC} sec later..."
          EM.add_timer(DELAY_SEC) { conn.reconnect }
        end
        connection
      end

      def create_channel(connection, prefetch=true)
        prefetch_opts = ( prefetch ? {:prefetch => 1} : {} )
        channel = AMQP::Channel.new(connection, connection.next_channel_id, prefetch_opts)
        channel.auto_recovery = true
        channel.on_error do |ch, error|
          if error.reply_code == 406 #PRECONDITION_FAILED
            cleanup_rabbitmq_stuff
          else
            Astute.logger.fatal "Channel error #{error.pretty_inspect}"
          end
          sleep DELAY_SEC # avoid race condition
          stop
        end
        channel
      end

      def connection_options
        {
          :host => Astute.config.broker_host,
          :port => Astute.config.broker_port,
          :username => Astute.config.broker_username,
          :password => Astute.config.broker_password,
        }.reject{|k, v| v.nil? }
      end

      def stop_event_machine
        EM.stop_event_loop if EM.reactor_running?
      end

      def cleanup_rabbitmq_stuff
        Astute.logger.warn "Try to remove problem exchanges and queues"

        [Astute.config.broker_exchange, Astute.config.broker_service_exchange].each do |exchange|
          rest_delete("/api/exchanges/%2F/#{exchange}")
        end

        [Astute.config.broker_queue, Astute.config.broker_publisher_queue].each do |queue|
          rest_delete("/api/queues/%2F/#{queue}")
        end
      end

      def rest_delete(url)
        http = Net::HTTP.new(Astute.config.broker_host, Astute.config.broker_rest_api_port)
        request = Net::HTTP::Delete.new(url)
        request.basic_auth(Astute.config.broker_username, Astute.config.broker_password)

        response = http.request(request)

        case response.code.to_i
        when 204 then Astute.logger.debug "Successfully delete object at #{url}"
        when 404 then
        else
           Astute.logger.error "Failed to perform delete request. Debug information: "\
                               "http code: #{response.code}, message: #{response.message},"\
                               "body #{response.body}"
        end
      end

    end

  end #Server
end #Astute

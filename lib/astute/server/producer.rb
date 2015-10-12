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
  module Server
    class Producer
      def initialize(exchange)
        @exchange = exchange
        @publish_queue = Queue.new
        @publish_consumer = Thread.new do
          while true do
            msg = @publish_queue.pop
            publish_from_queue msg
          end
        end
      end

      def publish_from_queue(message)
        Astute.logger.info "Casting message to Nailgun:\n"\
                          "#{message[:message].pretty_inspect}"
        @exchange.publish(message[:message].to_json, message[:options])
      rescue => e
        Astute.logger.error "Error publishing message: #{e.message}"
      end

      def publish(message, options={})
        default_options = {
          :routing_key => Astute.config.broker_publisher_queue,
          :content_type => 'application/json'
        }
        options = default_options.merge(options)
        @publish_queue << {:message => message, :options => options}
      end

      def stop
        @publish_consumer.kill
      end

    end # Producer
  end #Server
end #Astute

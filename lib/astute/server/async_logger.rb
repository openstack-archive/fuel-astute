#    Copyright 2015 Mirantis, Inc.
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
require 'thread'

module Astute
  module Server

    module AsyncLogger
      def self.start_up(logger=Logger.new(STDOUT))
        @queue ||= Queue.new
        @shutdown = false
        @log = logger
        @thread = Thread.new { wrtie_message }
      end

      def self.shutdown
        #Shutting down will disallow anymore additions
        #to the queue, let the queue finish, then stop.
        @shutdown = true
        @thread.join
      end

      def self.add(severity, msg=nil)
        return if @shutdown

        @queue.push([severity, msg])
      end

      def self.debug(msg=nil)
        add(Logger::Severity::DEBUG, msg)
      end

      def self.info(msg=nil)
        add(Logger::Severity::INFO, msg)
      end

      def self.warn(msg=nil)
        add(Logger::Severity::WARN, msg)
      end

      def self.error(msg=nil)
        add(Logger::Severity::ERROR, msg)
      end

      def self.fatal(msg=nil)
        add(Logger::Severity::FATAL, msg)
      end

      def self.unknown(msg=nil)
        add(Logger::Severity::UNKNOWN, msg)
      end
    end

    private

    def self.wrtie_message
      until @shutdown do
        severity, msg = @queue.pop
        @log.add(severity, msg)
      end
    end

  end
end
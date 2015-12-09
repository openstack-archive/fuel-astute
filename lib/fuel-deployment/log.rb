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

require 'logger'

module Deployment

  # This module is used by other module for debug logging
  # @attr [Logger] logger
  module Log

    # Get the logger object
    # @return [Logger]
    def self.logger
      return @logger if @logger
      @logger = Logger.new STDOUT
    end

    # Set the logger object
    # @param [Logger] value
    # @raise Deployment::InvalidArgument if the object does not look like a logger
    # @return [Logger]
    def self.logger=(value)
      unless value.respond_to? :debug and value.respond_to? :warn and value.respond_to? :info
        raise Deployment::InvalidArgument.new self, 'The object does not look like a logger!', value
      end
      @logger = value
    end

    # Log message with level: debug
    # @param [String] message
    def debug(message)
      Deployment::Log.logger.debug "#{self}: #{message}"
    end

    # Log message with level: warn
    # @param [String] message
    def warn(message)
      Deployment::Log.logger.warn "#{self}: #{message}"
    end

    # Log message with level: info
    # @param [String] message
    def info(message)
      Deployment::Log.logger.info "#{self}: #{message}"
    end

  end
end

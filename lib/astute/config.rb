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


require 'symboltable'
require 'singleton'

module Astute
  class ConfigError < StandardError; end
  class UnknownOptionError < ConfigError
    attr_reader :name

    def initialize(name)
      super("Unknown config option #{name}")
      @name = name
    end
  end

  class MyConfig
    include Singleton
    attr_reader :configtable

    def initialize
      @configtable = SymbolTable.new
    end
  end

  class ParseError < ConfigError
    attr_reader :line

    def initialize(message, line)
      super(message)
      @line = line
    end
  end

  def self.config
    config = MyConfig.instance.configtable
    config.update(default_config) if config.empty?
    return config
  end

  def self.default_config
    conf = {}

    # Library settings
    conf[:PUPPET_TIMEOUT] = 90 * 60       # maximum time it waits for the whole deployment
    conf[:PUPPET_DEPLOY_INTERVAL] = 2     # sleep for ## sec, then check puppet status again
    conf[:PUPPET_FADE_TIMEOUT] = 120      # how long it can take for puppet to exit after dumping to last_run_summary
    conf[:MC_RETRIES] = 5                 # MClient tries to call mcagent before failure
    conf[:MC_RETRY_INTERVAL] = 1          # MClient sleeps for ## sec between retries
    conf[:PUPPET_FADE_INTERVAL] = 10      # retry every ## seconds to check puppet state if it was running
    conf[:PROVISIONING_TIMEOUT] = 90 * 60 # timeout for booting target OS in provision
    conf[:REBOOT_TIMEOUT] = 240           # how long it can take for node to reboot
    conf[:DUMP_TIMEOUT] = 3600            # maximum time it waits for the dump (meaningles to be larger
                                          # than the specified in timeout of execute_shell_command mcagent

    conf[:PUPPET_SSH_KEYS] = ['neutron', 'nova', 'ceph', 'mysql']  # name of ssh keys what will be generated
                                                        #and uploaded to all nodes before deploy
    conf[:MAX_NODES_PER_CALL] = 50        # how many nodes to deploy in one puppet call
    conf[:SSH_RETRIES] = 5                # SSH tries to call ssh client before failure
    conf[:SSH_RETRY_TIMEOUT] = 30         # SSH sleeps for ## sec between retries

    conf[:MAX_NODES_PER_REMOVE_CALL] = 10 # how many nodes to remove in one call
    conf[:NODES_REMOVE_INTERVAL] = 10     # sleeps for ## sec between remove calls

    conf[:DHCP_REPEAT] = 3                # Dhcp discover will be sended 3 times

    # Server settings
    conf[:broker_host] = 'localhost'
    conf[:broker_port] = 5672
    conf[:broker_rest_api_port] = 15672
    conf[:broker_username] = 'mcollective'
    conf[:broker_password] = 'mcollective'

    conf[:broker_service_exchange] = 'naily_service'
    conf[:broker_queue] = 'naily'
    conf[:broker_publisher_queue] = 'nailgun'
    conf[:broker_exchange] = 'nailgun'
    conf[:iops] = 150

    conf
  end
end

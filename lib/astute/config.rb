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
    conf[:puppet_timeout] = 90 * 60       # maximum time it waits for single puppet run
    conf[:puppet_deploy_interval] = 2     # sleep for ## sec, then check puppet status again
    conf[:puppet_fade_timeout] = 120      # how long it can take for puppet to exit after dumping to last_run_summary
    conf[:puppet_retries] = 2             # how many times astute will try to run puppet
    conf[:puppet_succeed_retries] = 0     # use this to rerun a puppet task again if it was successful (idempotency)
    conf[:puppet_module_path] = '/etc/puppet/modules' # where we should find basic modules for puppet
    conf[:puppet_noop_run] = false        # enable Puppet noop run
    conf[:mc_retries] = 10                # MClient tries to call mcagent before failure
    conf[:mc_retry_interval] = 1          # MClient sleeps for ## sec between retries
    conf[:puppet_fade_interval] = 30      # retry every ## seconds to check puppet state if it was running
    conf[:provisioning_timeout] = 90 * 60 # timeout for booting target OS in provision
    conf[:reboot_timeout] = 900           # how long it can take for node to reboot
    conf[:dump_timeout] = 3600            # maximum time it waits for the dump (meaningles to be larger
                                          # than the specified in timeout of execute_shell_command mcagent
    conf[:shell_timeout] = 300            # default timeout for shell task
    conf[:stop_timeout] = 600             # how long it can take for stop
    conf[:shell_cwd] = '/'                # default cwd for shell task
    conf[:rsync_options] = '-c -r --delete -l' # default rsync options
    conf[:keys_src_dir] = '/var/lib/fuel/keys' # path where ssh and openssl keys will be created
    conf[:puppet_ssh_keys] = [
      'neutron',
      'nova',
      'ceph',
      'mysql',
    ]  # name of ssh keys what will be generated and uploaded to all nodes before deploy
    conf[:puppet_keys] = [
      'mongodb'
    ] # name of keys what will be generated and uploaded to all nodes before deploy
    conf[:keys_dst_dir] = '/var/lib/astute' # folder where keys will be uploaded. Warning!
    conf[:max_nodes_per_call] = 50        # how many nodes to deploy simultaneously
    conf[:max_nodes_to_provision] = 50    # how many nodes to provision simultaneously
    conf[:ssh_retry_timeout] = 30         # SSH sleeps for ## sec between retries

    conf[:max_nodes_per_remove_call] = 10 # how many nodes to remove in one call
    conf[:nodes_remove_interval] = 10     # sleeps for ## sec between remove calls
    conf[:max_nodes_net_validation] = 10  # how many nodes will send in parallel test packets
                                          # during network verification
    conf[:dhcp_repeat] = 3                # Dhcp discover will be sended 3 times

    conf[:iops] = 120                     # Default IOPS master node IOPS performance
    conf[:splay_factor] = 180             # Formula: 20(amount of nodes nodes) div 120(iops) = 0.1667
                                          # 0.1667 / 180 = 30 sec. Delay between reboot command for first
                                          # and last node in group should be 30 sec. Empirical observation.
                                          # Please increase if nodes could not provisioning
    conf[:agent_nodiscover_file] = '/etc/nailgun-agent/nodiscover' # if this file in place, nailgun-agent will do nothing
    conf[:bootstrap_profile] = 'ubuntu_bootstrap' # use the Ubuntu based bootstrap by default
    conf[:graph_dot_dir] = "/var/lib/astute/graphs" # default dir patch for debug graph file
    conf[:enable_graph_file] = true  # enable debug graph records to file
    conf[:puppet_raw_report] = false # enable puppet detailed report

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

    conf[:fault_tolerance_feature] = true
    conf[:critical_nodes_feature] = true

    conf
  end
end

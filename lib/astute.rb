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

require 'astute/ruby_removed_functions'

require 'json'
require 'logger'
require 'shellwords'
require 'active_support/all'

require 'astute/ext/exception'
require 'astute/ext/deep_copy'
require 'astute/exceptions'
require 'astute/config'
require 'astute/logparser'
require 'astute/orchestrator'
require 'astute/deployment_engine'
require 'astute/network'
require 'astute/puppetd'
require 'astute/deployment_engine/nailyfact'
require 'astute/cobbler'
require 'astute/cobbler_manager'
require 'astute/dump'
require 'astute/post_deploy_actions'
require 'astute/post_deploy_actions/restart_radosgw'
require 'astute/post_deploy_actions/update_cluster_hosts_info'
require 'astute/post_deploy_actions/upload_cirros_image'
require 'astute/ssh'
require 'astute/ssh_actions/ssh_erase_nodes'
require 'astute/ssh_actions/ssh_hard_reboot'

# Server
require 'astute/server/worker'
require 'astute/server/server'
require 'astute/server/producer'
require 'astute/server/dispatcher'
require 'astute/server/reporter'

module Astute
  # Library
  autoload 'Context', 'astute/context'
  autoload 'MClient', 'astute/mclient'
  autoload 'ProxyReporter', 'astute/reporter'
  autoload 'NodesRemover', 'astute/nodes_remover'
  autoload 'Node', 'astute/node'
  autoload 'NodesHash', 'astute/node'
  autoload 'RedhatChecker', 'astute/redhat_checker'
  autoload 'Rsyslogd', 'astute/rsyslogd'
  LogParser.autoload :ParseDeployLogs, 'astute/logparser/deployment'
  LogParser.autoload :ParseProvisionLogs, 'astute/logparser/provision'
  LogParser.autoload :Patterns, 'astute/logparser/parser_patterns'

  LOG_PATH = '/var/log/astute.log'

  def self.logger
    unless @logger
      @logger = Logger.new(LOG_PATH)
      @logger.formatter = proc do |severity, datetime, progname, msg|
        severity_map = {
          'DEBUG' => 'debug',
          'INFO' => 'info',
          'WARN' => 'warning',
          'ERROR' => 'err',
          'FATAL' => 'crit'
        }

        "#{datetime.strftime("%Y-%m-%dT%H:%M:%S")} #{severity_map[severity]}: [#{Process.pid}] #{msg}\n"
      end
    end
    @logger
  end

  def self.logger=(logger)
    @logger = logger
  end

  config_file = '/opt/astute/astute.conf'
  Astute.config.update(YAML.load(File.read(config_file))) if File.exists?(config_file)
end

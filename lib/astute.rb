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
require 'yaml'
require 'logger'
require 'shellwords'
require 'active_support/all'
require 'pp'
require 'bunny'
require 'zlib'

require 'astute/ext/exception'
require 'astute/ext/deep_copy'
require 'astute/exceptions'
require 'astute/config'
require 'astute/logparser'
require 'astute/orchestrator'
require 'astute/deployment_engine'
require 'astute/network'
require 'astute/puppetd'
require 'astute/provision'
require 'astute/deployment_engine/granular_deployment'
require 'astute/cobbler'
require 'astute/cobbler_manager'
require 'astute/image_provision'
require 'astute/dump'
require 'astute/deploy_actions'
require 'astute/nailgun_hooks'
require 'astute/puppet_task'
require 'astute/task_manager'
require 'astute/pre_delete'
require 'astute/version'
require 'astute/server/async_logger'
require 'astute/reporter'
require 'astute/mclient'
require 'astute/context'
require 'astute/nodes_remover'
require 'astute/task'
require 'astute/task_deployment'
require 'astute/task_node'
require 'astute/task_proxy_reporter'
require 'astute/task_cluster'
require 'astute/common/reboot.rb'
require 'fuel_deployment'

['/astute/pre_deployment_actions/*.rb',
 '/astute/pre_deploy_actions/*.rb',
 '/astute/pre_node_actions/*.rb',
 '/astute/post_deploy_actions/*.rb',
 '/astute/post_deployment_actions/*.rb',
 '/astute/common_actions/*.rb',
 '/astute/tasks/*.rb'
 ].each do |path|
  Dir[File.dirname(__FILE__) + path].each{ |f| require f }
end

# Server
require 'astute/server/worker'
require 'astute/server/server'
require 'astute/server/producer'
require 'astute/server/dispatcher'
require 'astute/server/reporter'

module Astute
  # Library
  autoload 'Node', 'astute/node'
  autoload 'NodesHash', 'astute/node'
  autoload 'Rsyslogd', 'astute/rsyslogd'
  LogParser.autoload :ParseDeployLogs, 'astute/logparser/deployment'
  LogParser.autoload :ParseProvisionLogs, 'astute/logparser/provision'
  LogParser.autoload :ParseImageBuildLogs, 'astute/logparser/provision'
  LogParser.autoload :Patterns, 'astute/logparser/parser_patterns'

  LOG_PATH = '/var/log/astute.log'

  def self.logger
    unless @logger
      @logger = Logger.new(LOG_PATH)
      @logger.formatter = proc do |severity, datetime, progname, msg|
        severity_map = {
          'DEBUG' => 'DEBUG',
          'INFO' => 'INFO',
          'WARN' => 'WARNING',
          'ERROR' => 'ERROR',
          'FATAL' => 'CRITICAL'
        }

        "#{datetime.strftime("%Y-%m-%d %H:%M:%S")} #{severity_map[severity]} [#{Process.pid}] #{msg}\n"
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

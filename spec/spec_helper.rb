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

require 'simplecov'
require 'simplecov-rcov'
SimpleCov.formatter = SimpleCov::Formatter::RcovFormatter
SimpleCov.start

require 'tempfile'
require 'tmpdir'
require 'fileutils'
require 'date'
require 'yaml'
require 'rspec'
# Following require is needed for rcov to provide valid results
require 'rspec/autorun'

require File.join(File.dirname(__FILE__), '../lib/astute')
Dir[File.join(File.dirname(__FILE__), 'unit/fixtures/*.rb')].each { |file| require file }

# NOTE(mihgen): I hate to wait for unit tests to complete,
#               resetting time to sleep significantly increases tests speed
Astute.config.PUPPET_DEPLOY_INTERVAL = 0
Astute.config.PUPPET_FADE_INTERVAL = 0
Astute.config.PUPPET_FADE_TIMEOUT = 1
Astute.config.MC_RETRY_INTERVAL = 0
Astute.config.PROVISIONING_TIMEOUT = 0
Astute.config.REBOOT_TIMEOUT = 0
Astute.config.SSH_RETRY_TIMEOUT = 0
Astute.config.NODES_REMOVE_INTERVAL = 0
Astute.logger = Logger.new(STDERR)

RSpec.configure do |c|
  c.mock_with :mocha
end

module SpecHelpers
  def mock_rpcclient(discover_nodes=nil, timeout=nil)
    rpcclient = mock('rpcclient') do
      stubs(:progress=)
      unless timeout.nil?
        expects(:timeout=).with(timeout)
      else
        stubs(:timeout=)
      end

      if discover_nodes.nil?
        stubs(:discover)
      else
        expects(:discover).with(:nodes => discover_nodes.map { |x| x['uid'].to_s }).at_least_once
      end
    end
    Astute::MClient.any_instance.stubs(:rpcclient).returns(rpcclient)
    rpcclient
  end

  def mock_mc_result(result={})
    mc_res = {:statuscode => 0, :data => {}, :sender => '1'}
    mc_res.merge!(result)
    mock('mc_result') do
      stubs(:results).returns(mc_res)
      stubs(:agent).returns('mc_stubbed_agent')
    end
  end

  def mock_ctx(parser=nil)
    parser ||= Astute::LogParser::NoParsing.new
    ctx = mock
    ctx.stubs(:task_id)
    ctx.stubs(:deploy_log_parser).returns(parser)
    reporter = mock() do
      stubs(:report)
    end
    ctx.stubs(:reporter).returns(reporter)

    ctx
  end

  # Transform fixtures from nailgun format node['roles'] array to node['role'] string
  def nodes_with_role(data, role)
    data.select { |n| n['role'] == role }
  end

end

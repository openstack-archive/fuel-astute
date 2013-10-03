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


require File.join(File.dirname(__FILE__), "..", "spec_helper")
require 'mcollective'
require 'json'
include MCollective::RPC

NODE = "devnailgun.mirantis.com"

describe "MCollective" do
  context "When MC agent is up and running" do
    it "it should send echo message to MC agent and get it back" do
      data_to_send = "simple message of node '#{NODE}'"
      mc = rpcclient("fake")
      mc.progress = false
      mc.discover(:nodes => [NODE])
      stats = mc.echo(:msg => data_to_send)
      check_mcollective_result(stats)
      stats[0].results[:data][:msg].should eql("Hello, it is my reply: #{data_to_send}")
    end
  end
end

private

def check_mcollective_result(stats)
  stats.should have(1).items
  stats[0].results[:statuscode].should eql(0)
end

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


require File.join(File.dirname(__FILE__), '../spec_helper')

describe Astute::Versioning do
  include SpecHelpers

  before(:each) do
    @reporter = mock('reporter')
    @reporter.stub_everything
    @context = Astute::Context.new('1', @reporter)
    @versioning = Astute::Versioning.new(@context)
    version_result = {:sender=>"1",
                      :statusmsg=>"OK",
                      :data=>{:agents=>["puppetd", "systemtype", "rpcutil", "fake",
                                        "uploadfile", "puppetsync", "execute_shell_command",
                                        "erase_node", "net_probe", "discovery",  "version"],
                      :facts=>{"mcollective"=>"1"}, :classes=>[]}}
    noversion_result = {:sender=>"2",
                        :statusmsg=>"OK",
                        :data=>{:agents=>["puppetd", "systemtype", "rpcutil", "fake",
                                          "uploadfile", "puppetsync", "execute_shell_command",
                                          "erase_node", "net_probe", "discovery" ],
                        :facts=>{"mcollective"=>"1"}, :classes=>[]}}
    nodes = [{'uid' => '1'}, {'uid' => '2'}]

    version_result = mock_mc_result(version_result)
    noversion_result = mock_mc_result(noversion_result)

    result = {:sender=>"1", :statuscode=>0, :statusmsg=>"OK", :data=>{:version=>"6.1.0"}}
    mc_res = mock_mc_result(result)
    mc_timeout = 5

    rpcclient = mock_rpcclient()
    rpcclient.expects(:inventory).once.returns([version_result, noversion_result])
    rpcclient.expects(:get_version).once.returns([mc_res])
  end

  describe 'get_version' do
    it 'returns nodes with versions' do
      expect(@versioning.get_versions(["1", "2"])
      ).to eql([{"version"=>"6.1.0", "uid"=>"1"}, {"version"=>"6.0.0", "uid"=>"2"}])
    end
  end

  describe 'split_on_version' do
    it 'splits on version' do
      expect(@versioning.split_on_version(@reporter, '123123', ["1", "2"], '6.1.0')
      ).to eql([[{"version"=>"6.0.0", "uid"=>"2"}], [{"version"=>"6.1.0", "uid"=>"1"}]])
    end
  end
end

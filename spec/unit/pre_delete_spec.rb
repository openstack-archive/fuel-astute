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


require File.join(File.dirname(__FILE__), '../spec_helper')

describe '#check_ceph_osds' do
  include SpecHelpers

  let(:ctx) { mock_ctx }
  let(:success_result) { {"status"=>"ready"} }

  let(:mclient) do
    mclient = mock_rpcclient(nodes)
    Astute::MClient.any_instance.stubs(:rpcclient).returns(mclient)
    Astute::MClient.any_instance.stubs(:log_result).returns(mclient)
    Astute::MClient.any_instance.stubs(:check_results_with_retries).returns(mclient)
    mclient
  end

  def build_mcresult(stdout="", sender="1")
    rs = {:sender => sender, :data => {:stdout => stdout}}
    mcresult_mock = mock_mc_result(rs)
    mock_result = mock
    mock_result.stubs(:results).returns(rs)
    mock_result.stubs(:each).returns(mcresult_mock)
    [mock_result]
  end

  context 'no ceph-osd nodes' do
    let(:nodes) { [
        {"uid" => "1", "roles" => ["controller"]},
        {"uid" => "2", "roles" => ["compute"]}
      ]
    }

    it 'should do nothing if no nodes have ceph-osd role' do
      expect(Astute::PreDelete.check_ceph_osds(ctx, nodes)).to eq(success_result)
    end
  end

  context "nodes with running OSDs" do
    let(:nodes) { [
        {"uid" => "1", "roles" => ["compute", "ceph-osd"]}
      ]
    }
    let(:cmd) { "pgrep -c ceph-osd" }
    let(:error_result) do
      msg = "Ceph OSDs are still running on nodes: [\"1\"]. " \
            "You must stop the OSDs manually and wait for the Ceph " \
            "cluster to become healthy before deleting these nodes."
      {'status' => 'error', 'error' => msg}
    end

    it "should raise error with running OSDs" do
      mclient.expects(:execute).with({:cmd => cmd}).returns(build_mcresult(stdout="1"))

      expect(Astute::PreDelete.check_ceph_osds(ctx, nodes)).to eq(error_result)
    end

    it "should succeed with no running OSD processes" do
      mclient.expects(:execute).with({:cmd => cmd}).returns(build_mcresult(stdout="0"))

      expect(Astute::PreDelete.check_ceph_osds(ctx, nodes)).to eq(success_result)
    end
  end

end # describe

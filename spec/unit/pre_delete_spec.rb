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

describe '#pre_delete_checks' do
  include SpecHelpers

  let(:ctx) { mock_ctx }
  let(:success_result) { {"status"=>"ready"} }

  let(:mclient) do
    mclient = mock_rpcclient
    Astute::MClient.any_instance.stubs(:rpcclient).returns(mclient)
    Astute::MClient.any_instance.stubs(:log_result).returns(mclient)
    Astute::MClient.any_instance.stubs(:check_results_with_retries).returns(mclient)
    mclient
  end

  def build_mcresult(stdout="", sender="1", exit_code=0)
    rs = {:sender => sender, :data => {:stdout => stdout, :exit_code => exit_code}}
    mcresult_mock = mock_mc_result(rs)
    mock_result = mock
    mock_result.stubs(:results).returns(rs)
    mock_result.stubs(:each).returns(mcresult_mock)
    [mock_result]
  end

  context "no ceph-osd nodes" do
    let(:nodes) { [
        {"id" => "1", "roles" => ["controller"]},
        {"id" => "2", "roles" => ["compute"]}
      ]
    }

    it "should do nothing if no nodes have ceph-osd role" do
      expect(Astute::PreDelete.check_ceph_osds(ctx, nodes)).to eq(success_result)
    end
  end

  context "nodes with ceph-osd role" do
    let(:nodes) { [
        {"id" => "1", "roles" => ["primary-controller"]},
        {"id" => "2", "roles" => ["compute", "ceph-osd"],
         "slave_name" => "node-2"}
      ]
    }
    let(:pg_cmd) {
      cmd = "ceph pg dump 2>/dev/null | " \
            "awk '//{print $14, $16}' | " \
            "egrep -o '\\<(1|2)\\>' | " \
            "sort -un"
    }
    let(:osd_cmd) { "ceph -f json osd tree" }
    let(:json_resp) { '{"nodes": [{"name": "node-2", "children": [1,2]}]}'}
    let(:error_result) do
      msg = "Ceph data still exists on: node-2. You must manually " \
            "remove the OSDs from the cluster and allow Ceph to " \
            "rebalance before deleting these nodes."
      {"status" => "error", "error" => msg}
    end

    it "should raise error if OSDs contain data" do
      mclient.expects(:execute).with({:cmd => osd_cmd})
        .returns(build_mcresult(stdout=json_resp))

      mclient.expects(:execute).with({:cmd => pg_cmd})
        .returns(build_mcresult(stdout="1\n2"))

      expect(Astute::PreDelete.check_ceph_osds(ctx, nodes)).to eq(error_result)
    end

    it 'should ignore nodes with unconfigured or failed ceph' do
      mclient.expects(:execute).with({:cmd => osd_cmd}).twice
        .returns(build_mcresult(stdout="","2", 42))
        .then.returns(build_mcresult(stdout=json_resp,"3", 1))

      mclient.expects(:execute).with({:cmd => pg_cmd}).never
      all_nodes = nodes + [{
        "id" => "3",
        "roles" => ["compute", "ceph-osd"],
        "slave_name" => "node-3"}
      ]
      expect(Astute::PreDelete.check_ceph_osds(ctx, all_nodes)).to eq(success_result)
    end

    it 'should find live ceph installation' do
      mclient.expects(:execute).with({:cmd => osd_cmd}).twice
        .returns(build_mcresult(stdout="","2", 42))
        .then.returns(build_mcresult(stdout=json_resp,"3", 0))

      mclient.expects(:execute).with({:cmd => pg_cmd})
        .returns(build_mcresult(stdout="1\n2"))

      all_nodes = nodes + [{
        "id" => "3",
        "roles" => ["compute", "ceph-osd"],
        "slave_name" => "node-3"}
      ]
      expect(Astute::PreDelete.check_ceph_osds(ctx, all_nodes)).to eq(error_result)
    end

    it "should succeed with no pgs placed on node" do
      mclient.expects(:execute).with({:cmd => osd_cmd})
        .returns(build_mcresult(stdout=json_resp))

      mclient.expects(:execute).with({:cmd => pg_cmd})
        .returns(build_mcresult(stdout="3\n4"))

      expect(Astute::PreDelete.check_ceph_osds(ctx, nodes)).to eq(success_result)
    end
  end

  context "verify that mcollective is running" do
    let(:nodes) { [
        {"id" => 1, "roles" => ["controller"]},
        {"id" => 2, "roles" => ["compute"]}
      ]
    }
    let(:error_result) do
      msg = "MCollective is not running on nodes 2. " \
            "MCollective must be running to properly delete a node."

      {"status" => "error",
       "error" => msg,
       "error_nodes" => [{"uid" => 2}]
      }
    end

    it "should prevent deletion of nodes when mcollective is not running" do
      rs = mock()
      rs.stubs(:map).returns([{:sender => "1"}])

      mclient.expects(:get_version).returns(rs)
      expect(Astute::PreDelete.check_for_offline_nodes(ctx, nodes)).to eq(error_result)
    end

    it "should allow deletion of nodes when mcollective is running" do
      rs = mock()
      rs.stubs(:map).returns( [
        {:sender => "1"},
        {:sender => "2"}
      ])
      mclient.expects(:get_version).returns(rs)

      expect(Astute::PreDelete.check_for_offline_nodes(ctx, nodes)).to eq(success_result)
    end
  end

end # describe

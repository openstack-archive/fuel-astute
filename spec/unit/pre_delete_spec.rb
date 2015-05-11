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

describe Astute::PreDelete do
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

  describe '#check_ceph_osds' do

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

  end # check_ceph_osds

  describe '#remove_ceph_mons' do

    let(:mon_cmd) { "ceph -f json mon dump" }
    let(:json_resp) do
      '{
        "epoch": 5,
        "mons": [
          {"name":"node-1", "addr":"192.168.0.11:6789\/0"},
          {"name":"node-2", "addr":"192.168.0.12:6789\/0"},
          {"name":"node-3", "addr":"192.168.0.13:6789\/0"}
        ]
      }'
    end

    def mon_rm_cmd(slave_name)
      "ceph mon remove #{slave_name}"
    end

    let(:nodes) { [
        {"id" => "1", "roles" => ["controller"], "slave_name" => "node-1"},
        {"id" => "2", "roles" => ["controller"], "slave_name" => "node-2"}
      ]
    }

    context "no ceph-mon nodes" do
      let(:nodes) { [
          {"id" => "3", "roles" => ["cinder"]},
          {"id" => "4", "roles" => ["compute"]}
        ]
      }

      it "should do nothing if no nodes have ceph-osd role" do
        expect(Astute::PreDelete.remove_ceph_mons(ctx, nodes)).to eq(success_result)
      end
    end

    it 'should ignore nodes with unconfigured or failed ceph mons' do
      mclient.expects(:execute).with({:cmd => mon_cmd}).twice
        .returns(build_mcresult(stdout="","1", 42))
        .then.returns(build_mcresult(stdout=json_resp,"2", 1))

      nodes.each do |node|
        mclient.expects(:execute).with({:cmd => mon_rm_cmd(node['slave_name'])}).never
      end

      expect(Astute::PreDelete.remove_ceph_mons(ctx, nodes)).to eq(success_result)
    end

    it 'should find and delete live ceph mon installation' do
      mclient.expects(:execute).with({:cmd => mon_cmd}).twice
        .returns(build_mcresult(stdout="","1", 42))
        .then.returns(build_mcresult(stdout=json_resp,"2", 0))

      nodes.each do |node|
        mclient.expects(:execute).with({:cmd => mon_rm_cmd(node['slave_name'])}).once
          .returns(build_mcresult(stdout="",node['id'], 0))
      end

      mclient.expects(:execute).with({:cmd =>
        "sed -i \"s/mon_initial_members.*/mon_initial_members = node-3/g\" /etc/ceph/ceph.conf"})
        .returns(build_mcresult(stdout="","3", 0))

      mclient.expects(:execute).with({:cmd =>
        "sed -i \"s/mon_host.*/mon_host = 192.168.0.13/g\" /etc/ceph/ceph.conf"})
        .returns(build_mcresult(stdout="","3", 0))

      expect(Astute::PreDelete.remove_ceph_mons(ctx, nodes)).to eq(success_result)
    end

  end # remove_ceph_mons

end

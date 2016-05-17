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

describe Astute::Network do
  include SpecHelpers

  let(:reporter) do
    reporter = mock('reporter')
    reporter.stub_everything
    reporter
  end

  def make_nodes(*uids)
    uids.map do |uid|
      {
        'uid' => uid,
        'networks' => [
          {
            'iface' => 'eth0',
            'vlans' => [100, 101]
          }
        ]
      }
    end
  end

  describe '.check_network' do

    it "should returns all vlans passed excluding incorrect" do
      nodes = make_nodes(1, 2)
      res1 = {
        :data => {
          :uid => "1",
          :neighbours => {
            "eth0" => {
              "100" => {"1" => ["eth0"], "2" => ["eth0"], "2th 2" => ["eth0"]},
              "101" => {"1" => ["eth0"]}
          }}},
        :sender => "1"}
      res2 = {
        :data => {
          :uid => "2",
          :neighbours => {
            "eth0" => {
              "100" => {"1" => ["eth0"], "2" => ["eth0"]},
              "101" => {"1" => ["eth0"], "2" => ["eth0"]}
            }}},
        :sender => "2"}
      valid_res = {:statuscode => 0, :sender => '1'}
      mc_res1 = mock_mc_result(res1)
      mc_res2 = mock_mc_result(res2)
      mc_valid_res = mock_mc_result

      rpcclient = mock_rpcclient(nodes)

      rpcclient.expects(:get_probing_info).once.returns([mc_res1, mc_res2])
      uids = nodes.map { |node| node['uid'].to_s }


      data_to_send = {}
      nodes[0]['networks'].each{ |net| data_to_send[net['iface']] = net['vlans'].join(",") }
      data_to_send = { '1' => data_to_send, '2' => data_to_send}

      rpcclient.expects(:start_frame_listeners).
        with(:interfaces => data_to_send.to_json).
        returns([mc_valid_res]*2)

      rpcclient.expects(:send_probing_frames).
        with(:interfaces => data_to_send.to_json).
        returns([mc_valid_res]*2)
      rpcclient.expects(:discover).with(:nodes => uids)
      Astute::MClient.any_instance.stubs(:rpcclient).returns(rpcclient)
      res = [[], [{"version"=>"6.1.0", "uid"=>"2"}, {"version"=>"6.1.0", "uid"=>"1"}]]
      Astute::Versioning.any_instance.stubs(:split_on_version).returns(res)

      res = Astute::Network.check_network(Astute::Context.new('task_uuid', reporter), nodes)
      expected = {"nodes" => [{"networks" => [{"iface"=>"eth0", "vlans"=>[100]}], "uid"=>"1"},
          {"networks"=>[{"iface"=>"eth0", "vlans"=>[100, 101]}], "uid"=>"2"}]}
      res.should eql(expected)
    end

    it "returns error if nodes list is empty" do
      res = Astute::Network.check_network(Astute::Context.new('task_uuid', reporter), [])
      res.should eql({'status' => 'error', 'error' => "Network verification requires a minimum of two nodes."})
    end

    it "returns all vlans passed if only one node provided" do
      nodes = make_nodes(1)
      res = Astute::Network.check_network(Astute::Context.new('task_uuid', reporter), nodes)
      expected = {"nodes" => [{"uid"=>1, "networks" => [{"iface"=>"eth0", "vlans"=>[100, 101]}]}]}
      res.should eql(expected)
    end

  end

  describe '.check_dhcp' do

    it "dhcp check should return expected info" do
      def mock_and_verify_check_dhcp(nodes, result, expected)
        rpcclient = mock_rpcclient(nodes)
        rpcclient.expects(:dhcp_discover).at_least_once.returns(result)
        Astute::MClient.any_instance.stubs(:rpcclient).returns(rpcclient)
        actual = Astute::Network.check_dhcp(Astute::Context.new('task_uuid', reporter), nodes)
        actual.should eql(expected)
      end

      nodes = make_nodes(1, 2)
      expected_data = [{'iface'=>'eth1',
                        'mac'=> 'ff:fa:1f:er:ds:as'},
                       {'iface'=>'eth2',
                        'mac'=> 'ee:fa:1f:er:ds:as'}]
      json_output = JSON.dump(expected_data)
      res1 = mock_mc_result({
        :data => {:out => json_output},
        :sender => "1"})
      res2 = mock_mc_result({
        :data => {:out => json_output},
        :sender => "2"})

      expected = {"nodes" => [{:status=>"ready", :uid=>"1", :data=>expected_data},
                              {:status=>"ready", :uid=>"2", :data=>expected_data}],
                  "status"=> "ready"}

      mock_and_verify_check_dhcp(nodes, [res1, res2], expected)

      # check case when the check failed for one of the nodes
      err_res = mock_mc_result({:sender => "1", :data => {:err => 'Test err'}})
      expected = {"nodes" => [{:uid => "1", :status => "error",
                               :error_msg => "Error in dhcp checker. Check logs for details"}],
                  "status" => "error"}
      mock_and_verify_check_dhcp([nodes[0]], [err_res], expected)

    end
  end

  describe '.multicast_verifcation' do

    def make_nodes(*uids)
      uids.map do |uid|
        {
          'uid' => uid.to_s,
          'iface' => 'eth1',
          'group' => '250.0.0.3',
          'port' => 10000
        }
      end
    end

    def format_nodes(nodes)
      formatted_nodes = {}
      nodes.each do |node|
        formatted_nodes[node['uid']] = node
      end
      formatted_nodes
    end

    it "must run all three stages: listen send info with expected argumenets" do
      nodes = make_nodes(1, 2)
      formatted_nodes = format_nodes(nodes)
      command_output = JSON.dump(["1", "2"])
      res1 = {:sender => "1",
              :data => {:out => command_output}}
      res2 = {:sender => "2",
              :data => {:out => command_output}}
      mc_valid_res = mock_mc_result
      expected_response = {1 => ["1", "2"],
                           2 => ["1", "2"]}

      rpcclient = mock_rpcclient()

      rpcclient.expects(:discover).with(:nodes=>formatted_nodes.keys)

      rpcclient.expects(:multicast_listen).with(:nodes=>formatted_nodes.to_json).once.returns([mock_mc_result]*2)

      rpcclient.expects(:multicast_send).with().once.returns([mock_mc_result]*2)

      rpcclient.expects(:multicast_info).with().once.returns([mock_mc_result(res1), mock_mc_result(res2)])

      res = Astute::Network.multicast_verification(Astute::Context.new('task_uuid', reporter), nodes)
      res['nodes'].should eql(expected_response)
    end

  end

  describe "check_vlans_by_traffic" do

    it "returns only tags from nodes in env" do
      data = {
              "eth0" => {
                "100" => {"1" => ["eth0"], "2" => ["eth0"], "3" => ["eth0"]},
                "101" => {"3" => ["eth0"]}
              },
            }
      correct_res = [{"iface"=>"eth0", "vlans"=>[100]}]
      uids = ["1", "2"]
      res = Astute::Network.check_vlans_by_traffic("1", uids, data)
      res.should eql(correct_res)
    end

    it "skips tags sent by node itself" do
      data = {
              "eth0" => {
                "100" => {"1" => ["eth0"], "2" => ["eth0"]},
                "101" => {"1" => ["eth0"]}
              },
            }
      correct_res = [{"iface"=>"eth0", "vlans"=>[100]}]
      uids = ["1", "2"]
      res = Astute::Network.check_vlans_by_traffic("1", uids, data)
      res.should eql(correct_res)
    end

    it "returns tags sent only by some nodes"do
      data = {
              "eth0" => {
                "100" => {"1" => ["eth0"], "2" => ["eth0"]},
                "101" => {"2" => ["eth0"]}
              },
            }
      correct_res = [{"iface"=>"eth0", "vlans"=>[100, 101]}]
      uids = ["1", "2"]
      res = Astute::Network.check_vlans_by_traffic("1", uids, data)
      res.should eql(correct_res)
    end

  end

  describe ".check_repositories_with_setup" do
    let(:nodes) do
        [
          {
            "iface"=>"eth1",
            "uid"=>"1",
            "vlan"=>0,
            "gateway"=>"10.109.1.1",
            "addr"=>"10.109.1.4/24",
            "urls"=>[
              "http://10.109.0.2:8080/2014.2.2-7.0/centos/auxiliary",
              "http://10.109.0.2:8080/2014.2.2-7.0/centos/x86_64"]
          },
          {
            "iface"=>"eth1",
            "uid"=>"4",
            "vlan"=>0,
            "gateway"=>"10.109.1.1",
            "addr"=>"10.109.1.4/24",
            "urls"=>[
              "http://10.109.0.2:8080/2014.2.2-7.0/centos/auxiliary",
              "http://10.109.0.2:8080/2014.2.2-7.0/centos/x86_64"]
          }
      ]
    end

    let(:mclient) do
      mclient = mock_rpcclient
      Astute::MClient.any_instance.stubs(:rpcclient).returns(mclient)
      Astute::MClient.any_instance.stubs(:log_result).returns(mclient)
      Astute::MClient.any_instance.stubs(:check_results_with_retries).returns(mclient)
      mclient
    end

    def build_mcresult(status=0, out="", err="", sender="1")
      rs = {:sender => sender, :data => {
        :status => status,
        :out => out,
        :err => err
      }}
      mcresult_mock = mock_mc_result(rs)
      mock_result = mock
      mock_result.stubs(:results).returns(rs)
      mock_result.stubs(:each).returns(mcresult_mock)
      mock_result
    end

    it "should check repositories with setup" do
      mclient.expects(:check_repositories_with_setup)
        .with({:data => {"1" => nodes.first, "4" => nodes.last}})
        .returns([
          build_mcresult(status=0),
          build_mcresult(status=0, out="", err="", sender="4")]
      )

      res = Astute::Network.check_repositories_with_setup(
        Astute::Context.new('task_uuid', reporter),
        nodes)

      res.should eql({
        "status"=>"ready",
        "nodes"=>[
          {:out=>"", :err=>"", :status=>0, :uid=>"1"},
          {:out=>"", :err=>"", :status=>0, :uid=>"4"}]
      })
    end

    it "should show error if repositories with setup do not return answer" do
      mclient.expects(:check_repositories_with_setup)
        .with({:data => {"1" => nodes.first, "4" => nodes.last}})
        .returns([
          build_mcresult(status=0)]
      )

      expect{Astute::Network.check_repositories_with_setup(
        Astute::Context.new('task_uuid', reporter),
        nodes)}.to raise_error(Astute::MClientTimeout, /check mcollective log/)
    end

  end

end

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

describe Astute::NodesRemover do
  include SpecHelpers

  let(:nodes) { [{'uid' => '1'}, {'uid' => '2'}] }
  let(:ctx) { mock_ctx }
  let(:ctl_time) { {'1' => '100', '2' => '200'} }

  let(:mcollective_answer) do
    [
      {:sender => '1', :statuscode => 0, :data => {:rebooted => true}},
      {:sender => '2', :statuscode => 0, :data => {:rebooted => true}}
    ]
  end

  before(:each) do
    Astute::NodesRemover.any_instance.stubs(:mclient_remove_piece_nodes).returns(mcollective_answer)
    Astute::NodesRemover.any_instance.stubs(:run_shell_without_check).returns(ctl_time)
  end

  it 'should erase nodes (mbr) and reboot nodes(default)' do
    expect(Astute::NodesRemover.new(ctx, nodes).remove).to eq({"nodes"=>[{"uid"=>"1"}, {"uid"=>"2"}]})
  end

  context 'nodes not answered by RPC' do
    let(:nodes) { [
        {'uid' => '1'},
        {'uid' => '2', 'mclient_remove' => true},
        {'uid' => '3', 'mclient_remove' => false}
    ]}
    let(:mcollective_answer) do
      [
        {:sender => '2', :statuscode => 0, :data => {:rebooted => true}}
      ]
    end

    it "should report inaccessible nodes" do
      expect(Astute::NodesRemover.new(ctx, nodes).remove).to eq(
        { "nodes" => [
            {'uid' => '3', 'mclient_remove' => false},
            {'uid' => '2'},
          ],
          "inaccessible_nodes" => [{"uid"=>"1", "error"=>"Node not answered by RPC.", "boot_time"=>100}]
        }
      )
    end
  end

  context 'some nodes will not be cleaned by mclient' do
    let(:nodes) { [
        {'uid' => '1'},
        {'uid' => '2', 'mclient_remove' => true},
        {'uid' => '3', 'mclient_remove' => false}
    ] }

    let(:mcollective_answer) do
      [
        {:sender => '1', :statuscode => 0, :data => {:rebooted => true}},
        {:sender => '2', :statuscode => 0, :data => {:rebooted => true}}
      ]
    end

    it "should call mclient only with 'mclient_remove' empty or set to true" do
      nr = Astute::NodesRemover.new(ctx, nodes)
      nr.stubs(:mclient_remove_nodes).with(
        Astute::NodesHash.build([
          {'uid' => '1', 'boot_time' => 100},
          {'uid' => '2', 'mclient_remove' => true, 'boot_time' => 200}
        ])
      ).returns(mcollective_answer).once
      nr.remove
    end
  end

  context 'nodes list empty' do
    it 'should do nothing if nodes list is empty' do
      Astute::NodesRemover.any_instance.expects(:mclient_remove_nodes).never
      expect(Astute::NodesRemover.new(ctx, []).remove).to eq({"nodes"=>[]})
    end
  end

  context 'nodes fail to erase' do
    let(:mcollective_answer) do
      [
        {:sender => '1', :statuscode => 1, :data => {:rebooted => false}},
        {:sender => '2', :statuscode => 1, :data => {:rebooted => false}}
      ]
    end

    it 'should inform about error' do
      expect(Astute::NodesRemover.new(ctx, nodes).remove).to eq(
        { "nodes"=>[],
          "status" => "error",
          "error_nodes" => [
          {"uid"=>"1", "error"=>"RPC agent 'erase_node' failed. Result:\n{:sender=>\"1\", :statuscode=>1, :data=>{:rebooted=>false}}\n", "boot_time"=>100},
          {"uid"=>"2", "error"=>"RPC agent 'erase_node' failed. Result:\n{:sender=>\"2\", :statuscode=>1, :data=>{:rebooted=>false}}\n", "boot_time"=>200}
          ]
        }
      )
    end

    it 'should try maximum mc_retries + 1 times to erase node if node get error' do
      retries = Astute.config[:mc_retries]
      expect(retries).to eq(10)

      remover = Astute::NodesRemover.new(ctx, nodes)
      remover.expects(:mclient_remove_nodes).times(retries + 1).returns(mcollective_answer)
      remover.remove
    end

    it 'should try maximum mc_retries + 1 times to erase node if node is inaccessible' do
      retries = Astute.config[:mc_retries]
      expect(retries).to eq(10)

      remover = Astute::NodesRemover.new(ctx, nodes)
      remover.expects(:mclient_remove_nodes).times(retries + 1).returns([])
      remover.remove
    end


    it 'should return success state if retry was succeed' do
      success_mcollective_answer = [
        {:sender => '1', :statuscode => 0, :data => {:rebooted => true}},
        {:sender => '2', :statuscode => 0, :data => {:rebooted => true}}
      ]
      Astute::NodesRemover.any_instance.stubs(:mclient_remove_nodes)
                                       .returns(mcollective_answer)
                                       .then.returns(success_mcollective_answer)

      expect(Astute::NodesRemover.new(ctx, nodes).remove).to eq({"nodes"=>[{"uid"=>"1"}, {"uid"=>"2"}]})
    end

  end

  context 'nodes fail to reboot' do
    let(:mcollective_answer) do
      [
        {:sender => '1', :statuscode => 0, :data => {:rebooted => false, :error_msg => 'Could not reboot'}},
        {:sender => '2', :statuscode => 0, :data => {:rebooted => false, :error_msg => 'Could not reboot'}}
      ]
    end

    it 'should inform about error' do
      expect(Astute::NodesRemover.new(ctx, nodes, reboot=true).remove).to eq(
        { "nodes"=>[],
          "status" => "error",
          "error_nodes" => [
            {"uid"=>"1", "error"=>"RPC method 'erase_node' failed with message: Could not reboot", "boot_time"=>100},
            {"uid"=>"2", "error"=>"RPC method 'erase_node' failed with message: Could not reboot", "boot_time"=>200}
          ]
        }
      )
    end
  end

  context 'nodes fail to send status, but erased and rebooted' do
    let(:mcollective_answer) do
      []
    end

    let(:ctl_time2) { {} }
    let(:ctl_time3) { {'1' => '150', '2' => '250'} }

    it 'should process rebooted nodes as erased' do
      Astute::NodesRemover.any_instance.stubs(:mclient_remove_piece_nodes).returns(mcollective_answer)
      Astute::NodesRemover.any_instance.stubs(:run_shell_without_check).returns(ctl_time)
                          .then.returns(ctl_time2).then.returns(ctl_time3)
      expect(Astute::NodesRemover.new(ctx, nodes, reboot=true).remove).to eq(
        { "nodes"=>[{"uid"=>"1"}, {"uid"=>"2"}] }
      )
    end
  end

  context 'erase node when change node status from bootstrap to provisioning' do
    let(:mcollective_answer) do
      [
        {:sender => '1', :statuscode => 0, :data => {:rebooted => false}},
        {:sender => '2', :statuscode => 0, :data => {:rebooted => false}}
      ]
    end

    it 'should erase nodes (mbr) and do not reboot nodes' do
      expect(Astute::NodesRemover.new(ctx, nodes, reboot=false).remove).to eq({"nodes"=>[{"uid"=>"1"}, {"uid"=>"2"}]})
    end
  end

  context 'nodes limits' do
    around(:each) do |example|
      old_value = Astute.config.max_nodes_per_remove_call
      example.run
      Astute.config.max_nodes_per_remove_call = old_value
    end

    let(:mcollective_answer1) do
      [{:sender => '1', :statuscode => 0, :data => {:rebooted => true}}]
    end

    let(:mcollective_answer2) do
      [{:sender => '2', :statuscode => 0, :data => {:rebooted => true}}]
    end

    before(:each) do
      Astute.config.max_nodes_per_remove_call = 1

      Astute::NodesRemover.any_instance.expects(:mclient_remove_piece_nodes).twice
                          .returns(mcollective_answer1)
                          .then.returns(mcollective_answer2)
    end

    it 'number of nodes deleting in parallel should be limited' do
      expect(Astute::NodesRemover.new(ctx, nodes).remove).to eq({"nodes"=>[{"uid"=>"1"}, {"uid"=>"2"}]})
    end

    it 'should sleep between group of nodes' do
      Astute::NodesRemover.any_instance.expects(:sleep).with(Astute.config.nodes_remove_interval)
      Astute::NodesRemover.new(ctx, nodes).remove
    end

    it 'should not use sleep for first group of nodes' do
      Astute::NodesRemover.any_instance.expects(:sleep).once
      Astute::NodesRemover.new(ctx, nodes).remove
    end
  end # nodes limits

  describe '#mclient_remove_piece_nodes' do
    it 'should get array of nodes uids' do
      remover = Astute::NodesRemover.new(ctx, nodes)
      remover.expects(:mclient_remove_piece_nodes).with(all_of(includes("1"), includes("2"))).returns(mcollective_answer)
      remover.remove
    end
  end

end # describe
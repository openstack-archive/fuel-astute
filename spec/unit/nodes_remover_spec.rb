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

  let(:mcollective_answer) do
    [
      {:sender => '1', :statuscode => 0, :data => {:rebooted => true}},
      {:sender => '2', :statuscode => 0, :data => {:rebooted => true}}
    ]
  end

  before(:each) do
    Astute::NodesRemover.any_instance.stubs(:mclient_remove_piece_nodes).returns(mcollective_answer)
  end

  it 'should erase nodes (mbr) and reboot nodes(default)' do
    expect(Astute::NodesRemover.new(ctx, nodes).remove).to eq({"nodes"=>[{"uid"=>"1"}, {"uid"=>"2"}]})
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

    it 'should infrom about error' do
      expect(Astute::NodesRemover.new(ctx, nodes).remove).to eq(
        { "nodes"=>[],
          "status" => "error",
          "error_nodes" => [
          {"uid"=>"1", "error"=>"RPC agent 'erase_node' failed. Result: {:sender=>\"1\", :statuscode=>1, :data=>{:rebooted=>false}}"},
          {"uid"=>"2", "error"=>"RPC agent 'erase_node' failed. Result: {:sender=>\"2\", :statuscode=>1, :data=>{:rebooted=>false}}"}
          ]
        }
      )
    end

    it 'should try maximum MC_RETRIES + 1 times to erase node if node get error' do
      retries = Astute.config[:MC_RETRIES]
      expect(retries).to eq(10)

      remover = Astute::NodesRemover.new(ctx, nodes)
      remover.expects(:mclient_remove_nodes).times(retries + 1).returns(mcollective_answer)
      remover.remove
    end

    it 'should try maximum MC_RETRIES + 1 times to erase node if node is inaccessible' do
      retries = Astute.config[:MC_RETRIES]
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

    it 'should infrom about error' do
      expect(Astute::NodesRemover.new(ctx, nodes, reboot=true).remove).to eq(
        { "nodes"=>[],
          "status" => "error",
          "error_nodes" => [
            {"uid"=>"1", "error"=>"RPC method 'erase_node' failed with message: Could not reboot"},
            {"uid"=>"2", "error"=>"RPC method 'erase_node' failed with message: Could not reboot"}
          ]
        }
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
      old_value = Astute.config.MAX_NODES_PER_REMOVE_CALL
      example.run
      Astute.config.MAX_NODES_PER_REMOVE_CALL = old_value
    end

    let(:mcollective_answer1) do
      [{:sender => '1', :statuscode => 0, :data => {:rebooted => true}}]
    end

    let(:mcollective_answer2) do
      [{:sender => '2', :statuscode => 0, :data => {:rebooted => true}}]
    end

    before(:each) do
      Astute.config.MAX_NODES_PER_REMOVE_CALL = 1

      Astute::NodesRemover.any_instance.expects(:mclient_remove_piece_nodes).twice
                          .returns(mcollective_answer1)
                          .then.returns(mcollective_answer2)
    end

    it 'number of nodes deleting in parallel should be limited' do
      expect(Astute::NodesRemover.new(ctx, nodes).remove).to eq({"nodes"=>[{"uid"=>"1"}, {"uid"=>"2"}]})
    end

    it 'should sleep between group of nodes' do
      Astute::NodesRemover.any_instance.expects(:sleep).with(Astute.config.NODES_REMOVE_INTERVAL)
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
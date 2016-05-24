#    Copyright 2016 Mirantis, Inc.
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

describe Astute::TaskCluster do
  include SpecHelpers

  subject { Astute::TaskCluster.new }

  let(:node) { Astute::TaskNode.new('node_name', subject) }

  before(:each) do
    subject.stubs(:validate_fault_tolerance)
  end

  describe "#hook_internal_post_node_poll" do
    it 'should call gracefully_stop with node' do
      subject.expects(:gracefully_stop).with(node)
      subject.hook_internal_post_node_poll(node)
    end
  end

  describe "#gracefully_stop" do
    it 'should check if node should be stopped' do
      subject.expects(:gracefully_stop?).returns(false)
      subject.hook_internal_post_node_poll(node)
    end

    it 'should check if node ready' do
      subject.stop_condition { true }
      node.expects(:ready?).returns(false)
      subject.hook_internal_post_node_poll(node)
    end

    it 'should set node status as skipped if stopped' do
      subject.stop_condition { true }
      node.stubs(:ready?).returns(true)
      node.stubs(:report_node_status)

      node.expects(:set_status_skipped).once
      subject.hook_internal_post_node_poll(node)
    end

    it 'should report new node status if stopped' do
      subject.stop_condition { true }
      node.stubs(:ready?).returns(true)
      node.stubs(:set_status_skipped).once

      node.expects(:report_node_status)
      subject.hook_internal_post_node_poll(node)
    end
  end

  it "should able to setup stop_condition" do
    expect(subject).to respond_to(:stop_condition)
  end

end

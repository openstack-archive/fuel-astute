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

include Astute

describe StopSignal do
  let(:stop_signal) { StopSignal.new }

  describe '#stop_deploy?' do
    it { should respond_to(:stop_deploy?).with(1).arguments }
    it { should_not respond_to(:stop_deploy?).with(0).argument }
    it 'should return boolean value' do
      result = stop_signal.stop_deploy?('task_id')
      expect {result.is_a?(TrueClass) || result.is_a?(FalseClass)}.to be_true
    end
  end
end
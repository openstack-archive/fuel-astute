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

require 'spec_helper'
require 'set'

describe Deployment::Concurrency::Counter do
  let(:counter) do
    Deployment::Concurrency::Counter.new(0, 0)
  end

  subject { counter }

  it 'can create an instance' do
    is_expected.to be_a Deployment::Concurrency::Counter
  end

  it 'can get the current value' do
    expect(subject.current).to eq 0
  end

  it 'can set the current value' do
    subject.current = 5
    expect(subject.current).to eq 5
  end

  it 'can get the maximum value' do
    expect(subject.maximum).to eq 0
  end

  it 'can set the maximum value' do
    subject.maximum = 5
    expect(subject.maximum).to eq 5
  end

  it 'can convert objects to values' do
    expect(subject.to_value 2).to eq 2
    expect(subject.to_value 0).to eq 0
    expect(subject.to_value '1').to eq 1
    expect(subject.to_value 'a').to eq 0
    expect(subject.to_value nil).to eq 0
    expect(subject.to_value []).to eq 0
    expect(subject.to_value true).to eq 0
  end

  it 'can increment the current value' do
    subject.current = 1
    subject.increment
    expect(subject.current).to eq 2
  end

  it 'can decrement the current value, but not below zero' do
    subject.current = 1
    subject.decrement
    expect(subject.current).to eq 0
    subject.decrement
    expect(subject.current).to eq 0
  end

  it 'can zero the current value' do
    subject.current = 5
    subject.zero
    expect(subject.current).to eq 0
  end

  it 'can check that counter is active - current value is less then maximum' do
    subject.maximum = 2
    subject.current = 1
    is_expected.to be_active
    is_expected.not_to be_inactive
  end

  it 'can check that counter is inactive - current value more then maximum' do
    subject.maximum = 1
    subject.current = 2
    is_expected.not_to be_active
    is_expected.to be_inactive
  end

  it 'is NOT active if the current value is equal to the maximum value' do
    subject.maximum = 2
    subject.current = 2
    is_expected.not_to be_active
  end

  it 'can check if the maximum value is set - is more then zero' do
    subject.maximum = 1
    is_expected.to be_maximum_set
    subject.maximum = 0
    is_expected.not_to be_maximum_set
  end

  it 'is active if the maximum value is not set regardless of the current value' do
    subject.current = 10
    subject.maximum = 1
    is_expected.not_to be_active
    subject.maximum = 0
    is_expected.to be_active
  end

end

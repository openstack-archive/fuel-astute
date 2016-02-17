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

describe Deployment::Concurrency::Group do
  let(:counter) do
    Deployment::Concurrency::Counter.new(0, 0)
  end

  let(:group) do
    group = Deployment::Concurrency::Group.new
    group['test'] = counter
    group
  end

  subject { group }

  it 'can create an instance' do
    is_expected.to be_a Deployment::Concurrency::Group
  end

  it 'has the group Hash attribute' do
    expect(subject.group).to be_a Hash
  end

  it 'can check if there is a Counter by its name' do
    expect(group.key? 'test').to eq true
    expect(group.key? 'missing').to eq false
  end

  it 'can get an existing counter' do
    expect(subject['test']).to eq counter
  end

  it 'can set an existing counter' do
    subject['test1'] = counter
    expect(subject['test1']).to eq counter
  end

  it 'can remove an existing counter' do
    expect(group.key? 'test').to eq true
    group.delete 'test'
    expect(group.key? 'test').to eq false
  end

  it 'will refuse to set an incorrect value' do
    expect do
      subject['a'] = 1
    end.to raise_error Deployment::InvalidArgument, /value should be a Counter/
  end

  it 'can create a new Counter in the group' do
    expect(group.key? 'my_counter').to eq false
    subject.create 'my_counter'
    expect(group.key? 'my_counter').to eq true
  end

  it 'will create a new instance of Counter if asked to get a nonexistent Counter' do
    expect(group.key? 'another_counter').to eq false
    expect(subject['another_counter']).to be_a Deployment::Concurrency::Counter
    expect(group.key? 'another_counter').to eq true
  end

  it 'can convert an object to a key' do
    expect(subject.to_key :a).to eq :a
    expect(subject.to_key 'a').to eq :a
    expect(subject.to_key 1).to eq :'1'
  end

  it 'will refuse to use a value that cannot be converted to a key' do
    expect do
      subject.to_key nil
    end.to raise_error Deployment::InvalidArgument, /cannot be used/
  end

  it 'can loop through all Counter objects' do
    expect(subject.each.to_a).to eq [counter]
  end

  it 'can act as an Enumerable container with Counters' do
    maximum_values = subject.map do |counter|
      counter.maximum
    end
    expect(maximum_values).to eq [0]
  end
end

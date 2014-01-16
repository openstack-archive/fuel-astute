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

describe MClient do
  include SpecHelpers

  before(:each) do
    @ctx = mock('context')
    @ctx.stubs(:task_id)
    @ctx.stubs(:reporter)
  end

  it "should receive method call and process valid result correctly" do
    nodes = [{'uid' => 1}, {'uid' => 2}, {'uid' => 3}]
    rpcclient = mock_rpcclient(nodes)
    mc_valid_result = mock_mc_result

    rpcclient.expects(:echo).with(:msg => 'hello world').once.returns([mc_valid_result]*3)

    mclient = MClient.new(@ctx, "faketest", nodes.map {|x| x['uid']})
    stats = mclient.echo(:msg => 'hello world')
    stats.should eql([mc_valid_result]*3)
  end

  it "should return even bad result if check_result=false" do
    nodes = [{'uid' => 1}, {'uid' => 2}, {'uid' => 3}]
    rpcclient = mock_rpcclient(nodes)
    mc_valid_result = mock_mc_result
    mc_error_result = mock_mc_result({:statuscode => 1, :sender => '2'})

    rpcclient.expects(:echo).with(:msg => 'hello world').once.\
        returns([mc_valid_result, mc_error_result])

    mclient = MClient.new(@ctx, "faketest", nodes.map {|x| x['uid']}, check_result=false)
    stats = mclient.echo(:msg => 'hello world')
    stats.should eql([mc_valid_result, mc_error_result])
  end

  it "should try to retry for non-responded nodes" do
    nodes = [{'uid' => 1}, {'uid' => 2}, {'uid' => 3}]
    rpcclient = mock('rpcclient') do
      stubs(:progress=)
      expects(:discover).with(:nodes => ['1','2','3'])
      expects(:discover).with(:nodes => ['2','3'])
    end
    Astute::MClient.any_instance.stubs(:rpcclient).returns(rpcclient)

    mc_valid_result = mock_mc_result
    mc_valid_result2 = mock_mc_result({:sender => '2'})

    rpcclient.stubs(:echo).returns([mc_valid_result]).then.
                           returns([mc_valid_result2])

    mclient = MClient.new(@ctx, "faketest", nodes.map {|x| x['uid']})
    mclient.retries = 1
    expect { mclient.echo(:msg => 'hello world') }.to \
      raise_error(Astute::MClientTimeout, /MCollective agents '3' didn't respond./)
  end

  it "should raise error if agent returns statuscode != 0" do
    nodes = [{'uid' => 1}, {'uid' => 2}, {'uid' => 3}]
    rpcclient = mock('rpcclient') do
      stubs(:progress=)
      expects(:discover).with(:nodes => ['1','2','3'])
      expects(:discover).with(:nodes => ['2','3'])
    end
    Astute::MClient.any_instance.stubs(:rpcclient).returns(rpcclient)

    mc_valid_result = mock_mc_result
    mc_failed_result = mock_mc_result({:sender => '2', :statuscode => 1})

    rpcclient.stubs(:echo).returns([mc_valid_result]).then.
                           returns([mc_failed_result]).then.
                           returns([mc_failed_result])

    mclient = MClient.new(@ctx, "faketest", nodes.map {|x| x['uid']})
    mclient.retries = 1
    expect { mclient.echo(:msg => 'hello world') }.to \
        raise_error(Astute::MClientError, /ID: 2 - Reason:/)
  end
end

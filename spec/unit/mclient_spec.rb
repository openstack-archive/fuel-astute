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

  let(:nodes) { [{'uid' => 1}, {'uid' => 2}, {'uid' => 3}] }

  it "should receive method call and process valid result correctly" do
    rpcclient = mock_rpcclient(nodes)
    mc_valid_result = mock_mc_result

    rpcclient.expects(:echo).with(:msg => 'hello world').once.returns([mc_valid_result]*3)

    mclient = MClient.new(@ctx, "faketest", nodes.map {|x| x['uid']})
    stats = mclient.echo(:msg => 'hello world')
    stats.should eql([mc_valid_result]*3)
  end

  it "should return even bad result if check_result=false" do
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

    mclient = MClient.new(@ctx, "faketest", nodes.map {|x| x['uid']}, check_result=true, timeout=nil, retries=1)
    expect { mclient.echo(:msg => 'hello world') }.to \
      raise_error(Astute::MClientTimeout, /MCollective agents '3' didn't respond./)
  end

  it "should raise error if agent returns statuscode != 0" do
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

  context 'initialize' do
    before(:each) do
      Astute::MClient.any_instance.stubs(:sleep)
    end

    it 'should try to initialize mclient 3 times' do
      rpcclient = mock('rpcclient') do
        stubs(:progress=)
        stubs(:discover).with(:nodes => ['1','2','3'])
          .raises(RuntimeError, 'test exception')
          .then.raises(RuntimeError, 'test exception')
          .then.returns(nil)
      end

      Astute::MClient.any_instance.stubs(:rpcclient).returns(rpcclient)
      mc_valid_result = mock_mc_result

      rpcclient.expects(:echo).with(:msg => 'hello world').once.returns([mc_valid_result]*3)

      mclient = MClient.new(@ctx, "faketest", nodes.map {|x| x['uid']})
      stats = mclient.echo(:msg => 'hello world')
      stats.should eql([mc_valid_result]*3)
    end

    it 'should raise error if initialize process fail after 3 attempts' do
      rpcclient = mock('rpcclient') do
        stubs(:progress=)
        stubs(:discover).with(:nodes => ['1','2','3'])
          .raises(RuntimeError, 'test exception').times(3)
      end

      Astute::MClient.any_instance.stubs(:rpcclient).returns(rpcclient)

      expect { MClient.new(@ctx, "faketest", nodes.map {|x| x['uid']}) }.to \
        raise_error(Astute::MClientError, /test exception/)
    end

    it 'should sleep 5 seconds between attempts' do
      rpcclient = mock('rpcclient') do
        stubs(:progress=)
        stubs(:discover).with(:nodes => ['1','2','3'])
          .raises(RuntimeError, 'test exception').times(3)
      end

      Astute::MClient.any_instance.stubs(:rpcclient).returns(rpcclient)

      Astute::MClient.any_instance.expects(:sleep).with(5).times(2)
      expect { MClient.new(@ctx, "faketest", nodes.map {|x| x['uid']}) }.to \
        raise_error(Astute::MClientError, /test exception/)
    end
  end # 'initialize'

  context 'mcollective call' do
    before(:each) do
      Astute::MClient.any_instance.stubs(:sleep)
    end

    it 'should retries 3 times' do
      rpcclient = mock_rpcclient(nodes)
      mc_valid_result = mock_mc_result

      mclient = MClient.new(@ctx, "faketest", nodes.map {|x| x['uid']}, check_result=false)
      rpcclient.stubs(:send)
        .raises(RuntimeError, 'test exception')
        .then.raises(RuntimeError, 'test exception')
        .then.returns([mc_valid_result])

      stats = mclient.echo(:msg => 'hello world')
      stats.should eql([mc_valid_result])
    end

    it 'should raise exception if process fail after 3 attempts' do
      rpcclient = mock_rpcclient(nodes)

      mclient = MClient.new(@ctx, "faketest", nodes.map {|x| x['uid']}, check_result=false)
      rpcclient.stubs(:send)
        .raises(RuntimeError, 'test send exception').times(3)

      expect { mclient.echo(:msg => 'hello world') }.to \
        raise_error(Astute::MClientError, /test send exception/)
    end

    it 'should sleep rand time before repeat' do
      rpcclient = mock_rpcclient(nodes)
      mc_valid_result = mock_mc_result

      mclient = MClient.new(@ctx, "faketest", nodes.map {|x| x['uid']}, check_result=false)
      rpcclient.stubs(:send)
        .raises(RuntimeError, 'test exception')
        .then.raises(RuntimeError, 'test exception')
        .then.returns([mc_valid_result])

      Astute::MClient.any_instance.expects(:sleep).times(2)
      stats = mclient.echo(:msg => 'hello world')
      stats.should eql([mc_valid_result])
    end
  end # 'mcollective call'

end # 'describe'

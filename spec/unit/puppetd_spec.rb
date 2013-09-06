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

describe "Puppetd" do
  include SpecHelpers

  context "PuppetdDeployer" do
    before :each do
      @ctx = mock
      @ctx.stubs(:task_id)
      @reporter = mock('reporter')
      @ctx.stubs(:reporter).returns(ProxyReporter::DeploymentProxyReporter.new(@reporter))
      @ctx.stubs(:deploy_log_parser).returns(Astute::LogParser::NoParsing.new)
    end

    it "reports ready status for node if puppet deploy finished successfully" do
      @reporter.expects(:report).with('nodes' => [{'uid' => '1', 'status' => 'ready', 'progress' => 100}])
      last_run_result = {:data=>
          {:time=>{"last_run"=>1358425701},
           :status => "running", :resources => {'failed' => 0},
           :running => 1, :idling => 0},
           :sender=>"1"}
      last_run_result_new = Marshal.load(Marshal.dump(last_run_result))
      last_run_result_new[:data][:time]['last_run'] = 1358426000

      last_run_result_finished = Marshal.load(Marshal.dump(last_run_result))
      last_run_result_finished[:data][:status] = 'stopped'
      last_run_result_finished[:data][:time]['last_run'] = 1358427000

      nodes = [{'uid' => '1'}]

      rpcclient = mock_rpcclient(nodes)

      rpcclient_valid_result = mock_mc_result(last_run_result)
      rpcclient_new_res = mock_mc_result(last_run_result_new)
      rpcclient_finished_res = mock_mc_result(last_run_result_finished)

      rpcclient.stubs(:last_run_summary).returns([rpcclient_valid_result]).then.
          returns([rpcclient_valid_result]).then.
          returns([rpcclient_new_res]).then.
          returns([rpcclient_finished_res])

      rpcclient.expects(:runonce).at_least_once.returns([rpcclient_valid_result])

      Astute::PuppetdDeployer.deploy(@ctx, nodes, retries=0)
    end

    it "doesn't report ready status for node if change_node_status disabled" do
      @reporter.expects(:report).never
      last_run_result = {:data=>
          {:time=>{"last_run"=>1358425701},
           :status => "running", :resources => {'failed' => 0},
           :running => 1, :idling => 0},
           :sender=>"1"}
      last_run_result_new = Marshal.load(Marshal.dump(last_run_result))
      last_run_result_new[:data][:time]['last_run'] = 1358426000

      last_run_result_finished = Marshal.load(Marshal.dump(last_run_result))
      last_run_result_finished[:data][:status] = 'stopped'
      last_run_result_finished[:data][:time]['last_run'] = 1358427000

      nodes = [{'uid' => '1'}]

      rpcclient = mock_rpcclient(nodes)

      rpcclient_valid_result = mock_mc_result(last_run_result)
      rpcclient_new_res = mock_mc_result(last_run_result_new)
      rpcclient_finished_res = mock_mc_result(last_run_result_finished)

      rpcclient.stubs(:last_run_summary).returns([rpcclient_valid_result]).then.
          returns([rpcclient_valid_result]).then.
          returns([rpcclient_new_res]).then.
          returns([rpcclient_finished_res])

      rpcclient.expects(:runonce).at_least_once.returns([rpcclient_valid_result])

      Astute::PuppetdDeployer.deploy(@ctx, nodes, retries=0, change_node_status=false)
    end


    context "puppet state transitions" do
      before :each do
        @last_run_result = {:statuscode=>0, :data=>
            {:changes=>{"total"=>1}, :time=>{"last_run"=>1358425701},
             :resources=>{"failed"=>0}, :status => "stopped", :enabled => 1,
             :stopped => 1, :idling => 0, :running => 0, :runtime => 1358425701},
                           :sender=>"1"}

        @last_run_result_idle_pre = Marshal.load(Marshal.dump(@last_run_result))
        @last_run_result_idle_pre[:data].update(
            {:status => 'idling', :idling => 1, :stopped => 0}
        )

        @last_run_result_running = Marshal.load(Marshal.dump(@last_run_result))
        @last_run_result_running[:data].update(
            {:status => 'running', :running => 1, :stopped => 0}
        )

        @last_run_result_finishing = Marshal.load(Marshal.dump(@last_run_result_running))
        @last_run_result_finishing[:data].update(
            {
                :runtime => 1358426000, :time => {"last_run" => 1358426000},
                :resources => {"failed" => 1}
            }
        )

        @last_run_result_idle_post = Marshal.load(Marshal.dump(@last_run_result_finishing))
        @last_run_result_idle_post[:data].update(
            {:status => 'idling', :idling => 1, :running => 0}
        )

        @last_run_result_finished = Marshal.load(Marshal.dump(@last_run_result_finishing))
        @last_run_result_finished[:data].update(
            {:status => 'stopped', :stopped => 1, :running => 0}
        )

        @nodes = [{'uid' => '1'}]
      end

      after :each do
        MClient.any_instance.unstub(:rpcclient)
      end

      it "publishes error status for node if puppet failed (a full cycle)" do
        @reporter.expects(:report).with('nodes' => [{'status' => 'error', 'error_type' => 'deploy', 'uid' => '1'}])
        @rpcclient = mock_rpcclient(@nodes)
        @rpcclient.stubs(:last_run_summary).times(9).
          returns([ mock_mc_result(@last_run_result) ]).then.
          returns([ mock_mc_result(@last_run_result) ]).then.
          returns([ mock_mc_result(@last_run_result_idle_pre) ]).then.
          returns([ mock_mc_result(@last_run_result_idle_pre) ]).then.
          returns([ mock_mc_result(@last_run_result_running) ]).then.
          returns([ mock_mc_result(@last_run_result_running) ]).then.
          returns([ mock_mc_result(@last_run_result_finishing) ]).then.
          returns([ mock_mc_result(@last_run_result_idle_post) ]).then.
          returns([ mock_mc_result(@last_run_result_finished) ])
        @rpcclient.expects(:runonce).once.
          returns([ mock_mc_result(@last_run_result) ])
        Astute::PuppetdDeployer.deploy(@ctx, @nodes, 0)
      end

      it "publishes error status for node if puppet failed (a cycle w/o idle states)" do
        @reporter.expects(:report).with('nodes' => [{'status' => 'error', 'error_type' => 'deploy', 'uid' => '1'}])
        @rpcclient = mock_rpcclient(@nodes)
        @rpcclient.stubs(:last_run_summary).times(6).
          returns([ mock_mc_result(@last_run_result) ]).then.
          returns([ mock_mc_result(@last_run_result) ]).then.
          returns([ mock_mc_result(@last_run_result_running) ]).then.
          returns([ mock_mc_result(@last_run_result_running) ]).then.
          returns([ mock_mc_result(@last_run_result_finishing) ]).then.
          returns([ mock_mc_result(@last_run_result_finished) ])
        @rpcclient.expects(:runonce).once.
          returns([ mock_mc_result(@last_run_result) ])
        Astute::PuppetdDeployer.deploy(@ctx, @nodes, 0)
      end

      it "publishes error status for node if puppet failed (a cycle w/o idle and finishing states)" do
        @reporter.expects(:report).with('nodes' => [{'status' => 'error', 'error_type' => 'deploy', 'uid' => '1'}])
        @rpcclient = mock_rpcclient(@nodes)
        @rpcclient.stubs(:last_run_summary).times(4).
          returns([ mock_mc_result(@last_run_result) ]).then.
          returns([ mock_mc_result(@last_run_result) ]).then.
          returns([ mock_mc_result(@last_run_result_running) ]).then.
          returns([ mock_mc_result(@last_run_result_finished) ])
        @rpcclient.expects(:runonce).once.
          returns([ mock_mc_result(@last_run_result) ])
        Astute::PuppetdDeployer.deploy(@ctx, @nodes, 0)
      end

      it "publishes error status for node if puppet failed (a cycle w/ one running state only)" do
        @reporter.expects(:report).with('nodes' => [{'status' => 'error', 'error_type' => 'deploy', 'uid' => '1'}])
        @rpcclient = mock_rpcclient(@nodes)
        @rpcclient.stubs(:last_run_summary).times(5).
          returns([ mock_mc_result(@last_run_result) ]).then.
          returns([ mock_mc_result(@last_run_result) ]).then.
          returns([ mock_mc_result(@last_run_result_running) ]).then.
          returns([ mock_mc_result(@last_run_result_finishing) ]).then.
          returns([ mock_mc_result(@last_run_result_finished) ])
        @rpcclient.expects(:runonce).once.
          returns([ mock_mc_result(@last_run_result) ])
        Astute::PuppetdDeployer.deploy(@ctx, @nodes, 0)
      end

      it "publishes error status for node if puppet failed (a cycle w/o any transitional states)" do
        @reporter.expects(:report).with('nodes' => [{'status' => 'error', 'error_type' => 'deploy', 'uid' => '1'}])
        @rpcclient = mock_rpcclient(@nodes)
        @rpcclient.stubs(:last_run_summary).times(3).
          returns([ mock_mc_result(@last_run_result) ]).then.
          returns([ mock_mc_result(@last_run_result) ]).then.
          returns([ mock_mc_result(@last_run_result_finished) ])
        @rpcclient.expects(:runonce).once.
          returns([ mock_mc_result(@last_run_result) ])
        Astute::PuppetdDeployer.deploy(@ctx, @nodes, 0)
      end
    end

    it "doesn't publish error status for node if change_node_status disabled" do
      @reporter.expects(:report).never

      last_run_result = {:statuscode=>0, :data=>
          {:changes=>{"total"=>1}, :time=>{"last_run"=>1358425701},
           :resources=>{"failed"=>0}, :status => "running",
           :running => 1, :idling => 0, :runtime => 100},
         :sender=>"1"}
      last_run_result_new = Marshal.load(Marshal.dump(last_run_result))
      last_run_result_new[:data][:time]['last_run'] = 1358426000
      last_run_result_new[:data][:resources]['failed'] = 1

      nodes = [{'uid' => '1'}]

      last_run_result_finished = Marshal.load(Marshal.dump(last_run_result))
      last_run_result_finished[:data][:status] = 'stopped'
      last_run_result_finished[:data][:time]['last_run'] = 1358427000
      last_run_result_finished[:data][:resources]['failed'] = 1

      rpcclient = mock_rpcclient(nodes)

      rpcclient_valid_result = mock_mc_result(last_run_result)
      rpcclient_new_res = mock_mc_result(last_run_result_new)
      rpcclient_finished_res = mock_mc_result(last_run_result_finished)

      rpcclient.stubs(:last_run_summary).returns([rpcclient_valid_result]).then.
          returns([rpcclient_valid_result]).then.
          returns([rpcclient_new_res]).then.
          returns([rpcclient_finished_res])
      rpcclient.expects(:runonce).at_least_once.returns([rpcclient_valid_result])

      MClient.any_instance.stubs(:rpcclient).returns(rpcclient)
      Astute::PuppetdDeployer.deploy(@ctx, nodes, retries=0, change_node_status=false)
    end

    it "retries to run puppet if it fails" do
      @reporter.expects(:report).with('nodes' => [{'uid' => '1', 'status' => 'ready', 'progress' => 100}])

      last_run_result = {:statuscode=>0, :data=>
          {:changes=>{"total"=>1}, :time=>{"last_run"=>1358425701},
           :resources=>{"failed"=>0}, :status => "running",
           :running => 1, :idling => 0, :runtime => 100},
         :sender=>"1"}
      last_run_failed = Marshal.load(Marshal.dump(last_run_result))
      last_run_failed[:data][:time]['last_run'] = 1358426000
      last_run_failed[:data][:resources]['failed'] = 1
      last_run_failed[:data][:status] = 'stopped'

      last_run_fixing = Marshal.load(Marshal.dump(last_run_result))
      last_run_fixing[:data][:time]['last_run'] = 1358426000
      last_run_fixing[:data][:resources]['failed'] = 1
      last_run_fixing[:data][:status] = 'running'

      last_run_success = Marshal.load(Marshal.dump(last_run_result))
      last_run_success[:data][:time]['last_run'] = 1358428000
      last_run_success[:data][:status] = 'stopped'

      nodes = [{'uid' => '1'}]

      rpcclient = mock_rpcclient(nodes)

      rpcclient_valid_result = mock_mc_result(last_run_result)
      rpcclient_failed = mock_mc_result(last_run_failed)
      rpcclient_fixing = mock_mc_result(last_run_fixing)
      rpcclient_succeed = mock_mc_result(last_run_success)

      rpcclient.stubs(:last_run_summary).returns([rpcclient_valid_result]).then.
          returns([rpcclient_valid_result]).then.
          returns([rpcclient_failed]).then.
          returns([rpcclient_failed]).then.
          returns([rpcclient_fixing]).then.
          returns([rpcclient_succeed])
      rpcclient.expects(:runonce).at_least_once.returns([rpcclient_valid_result])

      MClient.any_instance.stubs(:rpcclient).returns(rpcclient)
      Astute::PuppetdDeployer.deploy(@ctx, nodes, retries=1)
    end
  end
end

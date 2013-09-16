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
    let(:reporter) { mock('reporter') }
    
    let(:ctx) do
      Context.new("task id", ProxyReporter::DeploymentProxyReporter.new(reporter), Astute::LogParser::NoParsing.new)
    end
    
    let(:nodes) { [{'uid' => '1'}] }
    
    let(:rpcclient) { mock_rpcclient(nodes) }
    
    let(:last_run_result) do
      {
        :statuscode =>0,
        :data => {
          :changes => {"total" => 1},
          :time => {"last_run" => 1358425701},
          :resources => {"failed" => 0},
          :status => "stopped",
          :enabled => 1,
          :stopped => 1,
          :idling => 0,
          :running => 0,
          :runtime => 1358425701
        },
        :sender=>"1"
      }
    end
    
    let(:last_run_result_running) do
      res = deep_copy(last_run_result)
      res[:data].merge!(:status => 'running', :running => 1, :stopped => 0)
      res
    end
    
    let(:last_run_result_fail) do
      res = deep_copy(last_run_result_running)
      res[:data].merge!(:runtime => 1358426000, 
                        :time => {"last_run" => 1358426000},
                        :resources => {"failed" => 1}
                       )
      res
    end
    
    let(:last_run_failed) do
      res = deep_copy(last_run_result_fail)
      res[:data].merge!(:status => 'stopped', :stopped => 1, :running => 0)
      res
    end
    
    let(:last_run_result_finished) do
      res = deep_copy last_run_result
      res[:data][:time]['last_run'] = 1358428000
      res[:data][:status] = 'stopped'
      res
    end
    
    context 'reportet behavior' do
      let(:last_run_result) do
         {
           :data=> {
              :time=>{"last_run"=>1358425701},
              :status => "running", 
              :resources => {'failed' => 0},
              :running => 1, 
              :idling => 0
            },
            :sender=>"1"
          }
      end
    
      let(:prepare_mcollective_env) do
        last_run_result_new = deep_copy last_run_result
        last_run_result_new[:data][:time]['last_run'] = 1358426000
        
        rpcclient_new_res = mock_mc_result(last_run_result_new)
        rpcclient_finished_res = mock_mc_result(last_run_result_finished)
        rpcclient_valid_result = mock_mc_result(last_run_result)

        rpcclient.stubs(:last_run_summary).returns([rpcclient_valid_result]).then.
            returns([rpcclient_valid_result]).then.
            returns([rpcclient_new_res]).then.
            returns([rpcclient_finished_res])
        
        rpcclient
      end

      it "reports ready status for node if puppet deploy finished successfully" do
        prepare_mcollective_env
        
        reporter.expects(:report).with('nodes' => [{'uid' => '1', 'status' => 'ready', 'progress' => 100}])
        rpcclient.expects(:runonce).at_least_once.returns([mock_mc_result(last_run_result)])
        
        Astute::PuppetdDeployer.deploy(ctx, nodes, retries=0)
      end

      it "doesn't report ready status for node if change_node_status disabled" do
        prepare_mcollective_env
        
        reporter.expects(:report).never
        rpcclient.expects(:runonce).at_least_once.returns([mock_mc_result(last_run_result)])
        
        Astute::PuppetdDeployer.deploy(ctx, nodes, retries=0, change_node_status=false)
      end
    end

    context "puppet state transitions" do
      
      let(:last_run_result_idle_pre) do
        res = deep_copy(last_run_result)
        res[:data].merge!(:status => 'idling', :idling => 1, :stopped => 0)
        res
      end
      
      let(:last_run_result_idle_post) do
        res = deep_copy(last_run_result_fail)
        res[:data].merge!(:status => 'idling', :idling => 1, :running => 0)
        mock_mc_result res
      end

      it "publishes error status for node if puppet failed (a full cycle)" do
        rpcclient.stubs(:last_run_summary).times(9).
          returns([ mock_mc_result(last_run_result) ]).then.
          returns([ mock_mc_result(last_run_result) ]).then.
          returns([ mock_mc_result(last_run_result_idle_pre) ]).then.
          returns([ mock_mc_result(last_run_result_idle_pre) ]).then.
          returns([ mock_mc_result(last_run_result_running) ]).then.
          returns([ mock_mc_result(last_run_result_running) ]).then.
          returns([ mock_mc_result(last_run_result_fail) ]).then.
          returns([ mock_mc_result(last_run_result_fail) ]).then.
          returns([ mock_mc_result(last_run_failed) ])
        
        reporter.expects(:report).with('nodes' => [{'status' => 'error', 'error_type' => 'deploy', 'uid' => '1'}])
        rpcclient.expects(:runonce).once.
          returns([ mock_mc_result(last_run_result) ])
        
        Astute::PuppetdDeployer.deploy(ctx, nodes, 0)
      end

      it "publishes error status for node if puppet failed (a cycle w/o idle states)" do
        rpcclient.stubs(:last_run_summary).times(6).
          returns([ mock_mc_result(last_run_result) ]).then.
          returns([ mock_mc_result(last_run_result) ]).then.
          returns([ mock_mc_result(last_run_result_running) ]).then.
          returns([ mock_mc_result(last_run_result_running) ]).then.
          returns([ mock_mc_result(last_run_result_fail) ]).then.
          returns([ mock_mc_result(last_run_failed) ])
        
        reporter.expects(:report).with('nodes' => [{'status' => 'error', 'error_type' => 'deploy', 'uid' => '1'}])
        rpcclient.expects(:runonce).once.
          returns([ mock_mc_result(last_run_result) ])
        
        Astute::PuppetdDeployer.deploy(ctx, nodes, 0)
      end

      it "publishes error status for node if puppet failed (a cycle w/o idle and finishing states)" do
        rpcclient.stubs(:last_run_summary).times(4).
          returns([ mock_mc_result(last_run_result) ]).then.
          returns([ mock_mc_result(last_run_result) ]).then.
          returns([ mock_mc_result(last_run_result_running) ]).then.
          returns([ mock_mc_result(last_run_failed) ])
        
        reporter.expects(:report).with('nodes' => [{'status' => 'error', 'error_type' => 'deploy', 'uid' => '1'}])
        rpcclient.expects(:runonce).once.
          returns([ mock_mc_result(last_run_result) ])
        
        Astute::PuppetdDeployer.deploy(ctx, nodes, 0)
      end

      it "publishes error status for node if puppet failed (a cycle w/ one running state only)" do
        rpcclient.stubs(:last_run_summary).times(5).
          returns([ mock_mc_result(last_run_result) ]).then.
          returns([ mock_mc_result(last_run_result) ]).then.
          returns([ mock_mc_result(last_run_result_running) ]).then.
          returns([ mock_mc_result(last_run_result_fail) ]).then.
          returns([ mock_mc_result(last_run_failed) ])
        
        reporter.expects(:report).with('nodes' => [{'status' => 'error', 'error_type' => 'deploy', 'uid' => '1'}])
        rpcclient.expects(:runonce).once.
          returns([ mock_mc_result(last_run_result) ])
        
        Astute::PuppetdDeployer.deploy(ctx, nodes, 0)
      end

      it "publishes error status for node if puppet failed (a cycle w/o any transitional states)" do
        rpcclient.stubs(:last_run_summary).times(3).
          returns([ mock_mc_result(last_run_result) ]).then.
          returns([ mock_mc_result(last_run_result) ]).then.
          returns([ mock_mc_result(last_run_failed) ])
        
        reporter.expects(:report).with('nodes' => [{'status' => 'error', 'error_type' => 'deploy', 'uid' => '1'}])
        rpcclient.expects(:runonce).once.
          returns([ mock_mc_result(last_run_result) ])
        
        Astute::PuppetdDeployer.deploy(ctx, nodes, 0)
      end
    end

    it "doesn't publish error status for node if change_node_status disabled" do
      reporter.expects(:report).never

      rpcclient_valid_result = mock_mc_result(last_run_result)
      rpcclient_new_res = mock_mc_result(last_run_result_fail)
      rpcclient_finished_res = mock_mc_result(last_run_failed)

      rpcclient.stubs(:last_run_summary).returns([rpcclient_valid_result]).then.
          returns([rpcclient_valid_result]).then.
          returns([rpcclient_new_res]).then.
          returns([rpcclient_finished_res])
      rpcclient.expects(:runonce).at_least_once.returns([rpcclient_valid_result])

      MClient.any_instance.stubs(:rpcclient).returns(rpcclient)
      Astute::PuppetdDeployer.deploy(ctx, nodes, retries=0, change_node_status=false)
    end

    it "retries to run puppet if it fails" do
      rpcclient_valid_result = mock_mc_result(last_run_result)
      rpcclient_failed = mock_mc_result(last_run_failed)
      rpcclient_fail = mock_mc_result(last_run_result_fail)
      rpcclient_succeed = mock_mc_result(last_run_result_finished)

      rpcclient.stubs(:last_run_summary).returns([rpcclient_valid_result]).then.
          returns([rpcclient_valid_result]).then.
          returns([rpcclient_failed]).then.
          returns([rpcclient_failed]).then.
          returns([rpcclient_fail]).then.
          returns([rpcclient_succeed])
      
      reporter.expects(:report).with('nodes' => [{'uid' => '1', 'status' => 'ready', 'progress' => 100}])
      rpcclient.expects(:runonce).at_least_once.returns([rpcclient_valid_result])

      MClient.any_instance.stubs(:rpcclient).returns(rpcclient)
      Astute::PuppetdDeployer.deploy(ctx, nodes, retries=1)
    end
  end
end

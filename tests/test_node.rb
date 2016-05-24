#    Copyright 2015 Mirantis, Inc.
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

lib_dir = File.join File.dirname(__FILE__), '../lib'
lib_dir = File.absolute_path File.expand_path lib_dir
$LOAD_PATH << lib_dir

require 'rubygems'
require 'fuel_deployment'
require 'optparse'
require 'pry'

Deployment::Log.logger.level = Logger::INFO

def options
  return $options if $options
  $options = {}
  OptionParser.new do |opts|
    opts.on('-p', '--plot') do |value|
      options[:plot] = value
    end
    opts.on('-f', '--fail') do |value|
      options[:fail] = value
    end
    opts.on('-c', '--critical') do |value|
      options[:critical] = value
    end
    opts.on('-i', '--interactive') do |value|
      options[:interactive] = value
    end
    opts.on('-d', '--debug') do
      Deployment::Log.logger.level = Logger::DEBUG
    end
  end.parse!
  $options
end

module Deployment
  class TestNode < Node
    def fail_tasks
      return @fail_tasks if @fail_tasks
      @fail_tasks = []
    end

    def fail_tasks=(value)
      @fail_tasks = value
    end

    def run(task)
      fail Deployment::InvalidArgument, "#{self}: Node can run only tasks" unless task.is_a? Deployment::Task
      debug "Run task: #{task}"
      self.task = task
      self.status = :busy
    end

    def poll
      debug 'Poll node status'
      if busy?
        status = :successful
        status = :failed if fail_tasks.include? task
        debug "#{task} finished with: #{status}"
        self.task.status = status
        self.status = :online

        self.status = :skipped if task.status == :dep_failed
        self.status = :failed if task.status == :failed
      end
    end
  end

  class TestCluster < Cluster
    attr_accessor :plot
    def hook_pre_node(*args)
      make_image if plot
    end
  end
end

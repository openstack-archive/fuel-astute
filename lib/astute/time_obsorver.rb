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

require 'timeout'

module Astute
  class TimeObserver

    def initialize(timeout)
      @timeout = timeout
    end

    def start
      @time_before = Time.now
    end

    def stop
      (Time.now - @time_before).to_i
    end

    def enough_time?
      Time.now - @time_before < time_limit
    end

    def left_time
      time_limit - (Time.now - @time_before)
    end

    def time_limit
      @timeout
    end

  end #TimeObserver
end
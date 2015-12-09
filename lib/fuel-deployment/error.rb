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

module Deployment
  # This exception is raised if you have passed an incorrect object to a method
  class InvalidArgument < StandardError
    attr_reader :argument
    def initialize(object, message='Argument is invalid!', argument=nil)
      @argument = argument
      message = "#{object}: #{message}"
      message += " (#{argument})" if argument
      super(message)
    end
  end

  # There is no task with such name is the graph
  class NoSuchTask < StandardError
    attr_reader :task
    def initialize(object, message='There is no such task!', task=nil)
      @task = task
      message = "#{object}: #{message}"
      message += " Name: #{task}" if task
      super(message)
    end
  end

  # You have directly called an abstract method that should be implemented in a subclass
  class NotImplemented < StandardError
  end

  # Loop detected in the graph
  class LoopDetected < StandardError
    attr_reader :tasks
    def initialize(object, message='Loop detected!', tasks=[])
      @tasks = tasks
      message = "#{object}: #{message}"
      if tasks.any?
        message += " Path: #{tasks.join ', '}"
      end
      super(message)
    end
  end
end

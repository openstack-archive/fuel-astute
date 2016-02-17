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

module Deployment

  # The Concurrency module contains objects that implement the task
  # and node concurrency features.
  module Concurrency
    # The counter object can keep the current and maximum values,
    # increment and decrement them and check if the current value
    # is not bigger then the maximum value.
    # @attr current [Integer]
    # @attr maximum [Integer]
    class Counter
      def initialize(maximum=0, current=0)
        self.maximum = maximum
        self.current = current
      end

      attr_reader :current
      attr_reader :maximum

      # Set the current value of this counter
      # @param value [Integer]
      # @return [Integer]
      def current=(value)
        @current = to_value value
      end

      # Set the maximum value of this counter
      # @param value [Integer]
      # @return [Integer]
      def maximum=(value)
        @maximum = to_value value
      end

      # Convert a value to a positive integer
      # @param value [String,Integer]
      # @return [Integer]
      def to_value(value)
        begin
          value = Integer value
          return 0 unless value > 0
          value
        rescue
          0
        end
      end

      # Increase this counter's current value by one
      # @return [Integer]
      def increment
        self.current += 1
      end
      alias :inc :increment

      # Decrease this counter's current value by one
      # @return [Integer]
      def decrement
        self.current -= 1
      end
      alias :dec :decrement

      # Set this counter's current value to zero
      # @return [Integer]
      def zero
        self.current = 0
      end

      # Is the current value lesser or equal to the maximum value
      # @return [true,false]
      def active?
        return true unless maximum_set?
        current < maximum
      end
      alias :available? :active?

      # Is the current value bigger then the maximum value
      # @return [true,false]
      def inactive?
        not active?
      end
      alias :overflow? :inactive?

      # Check if the maximum value is set
      # @return [true,false]
      def maximum_set?
        maximum != 0
      end
    end
  end
end

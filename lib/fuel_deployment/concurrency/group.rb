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
  module Concurrency
    # The concurrency group can keep the collection on Counter
    # objects, create new ones and retrieve the saved ones by their name
    # @attr_reader group [Hash<Symbol => Deployment::Concurrency::Counter>]
    class Group
      def initialize
        @group = {}
      end

      attr_accessor :group

      include Enumerable

      # Loop through all defined Counter objects
      # @yield [Deployment::Concurrency::Counter]
      def each(&block)
        group.each_value(&block)
      end

      # Create a new Counter object by the given name
      # @param key [Symbol, String]
      # @return [Deployment::Concurrency::Counter]
      def create(key, *args)
        key = to_key key
        self.set key, Deployment::Concurrency::Counter.new(*args)
      end

      # Check if there is a concurrency object by this name
      # @param key [String,Symbol]
      # @return [true,false]
      def key?(key)
        key = to_key key
        @group.key? key
      end
      alias :exists? :key?

      # Assign a Concurrency object to a key
      # @param key [Symbol, String]
      # @param value [Deployment::Concurrency::Counter]
      # @return [Deployment::Concurrency::Counter]
      def set(key, value)
        raise Deployment::InvalidArgument.new self, 'The value should be a Counter object!', value unless value.is_a? Deployment::Concurrency::Counter
        key = to_key key
        @group[key] = value
      end
      alias :[]= :set

      # Remove a defined Counter object by its name
      # @param key [Symbol, String]
      def delete(key)
        key = to_key key
        @group.delete key if @group.key? key
      end
      alias :remove :delete

      # Retrieve a Concurrency object by the given name
      # or create a new one if there is no one saved ny this name
      # @param key [Symbol, String]
      # @return [Deployment::Concurrency::Counter]
      def get(key)
        key = to_key key
        return @group[key] if @group.key? key
        create key
      end
      alias :[] :get

      # Convert a value to symbol
      # @param key [Symbol,String]
      # @return [Symbol]
      def to_key(key)
        return key if key.is_a? Symbol
        processed_key = nil
        unless key.nil?
          begin
            processed_key = key.to_s.to_sym
          rescue
            nil
          end
        end
        raise Deployment::InvalidArgument.new self, "The value '#{key}' cannot be used as a concurrency name!" unless processed_key
        processed_key
      end
    end
  end
end

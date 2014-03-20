#    Copyright 2014 Mirantis, Inc.
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


require 'active_support/core_ext/hash/indifferent_access'
require 'ostruct'

module Astute
  class Node < OpenStruct
    def initialize(hash=nil)
      if hash && (uid = hash['uid'])
        hash = hash.dup
        hash['uid'] = uid.to_s
      else
        raise TypeError.new("Invalid data: #{hash.inspect}")
      end
      super hash
    end

    def [](key)
      send key
    end

    def []=(key, value)
      send "#{key}=", value
    end

    def uid
      @table[:uid]
    end

    def uid=(_)
      raise TypeError.new('Read-only attribute')
    end

    def to_hash
      @table.with_indifferent_access
    end
  end

  class NodesHash < Hash
    alias uids  keys
    alias nodes values

    def self.build(nodes)
      return nodes if nodes.kind_of? self
      nodes.inject(self.new) do |hash, node|
        hash << node
        hash
      end
    end

    def <<(node)
      node = normalize_value(node)
      self[node.uid] = node
      self
    end

    def push(*nodes)
      nodes.each{|node| self.<< node }
      self
    end

    def [](key)
      super key.to_s
    end

  private

    def []=(*args)
      super
    end

    def normalize_value(node)
      if node.kind_of? Node
        node
      else
        Node.new(node.to_hash)
      end
    end
  end
end
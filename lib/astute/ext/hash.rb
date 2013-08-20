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


class Hash
    
  # The value of the existing keys are not overridden
  def reverse_merge(another_hash)
    another_hash.merge(self)
  end
  
  def reverse_merge!(another_hash)
    replace(reverse_merge(another_hash))
  end
  
  def absent_keys(array)
    array.select { |key| absent?(key) }
  end
  
  def absent?(key)
    self[key].nil? || (self[key].respond_to?(:empty?) && self[key].empty?)
  end
  
  def present?(key)
    !absent?(key)
  end
  
  # def recursive_merge!(other)
  #   other.keys.each do |k|
  #     if self[k].is_a?(Array) && other[k].is_a?(Array)
  #       self[k] += other[k]
  #     elsif self[k].is_a?(Hash) && other[k].is_a?(Hash)
  #       self[k].recursive_merge!(other[k])
  #     else
  #       self[k] = other[k]
  #     end
  #   end
  #   self
  # end
  
  def deep_merge(other_hash)
    self.merge(other_hash) do |key, oldval, newval|
      oldval = oldval.to_hash if oldval.respond_to?(:to_hash)
      newval = newval.to_hash if newval.respond_to?(:to_hash)
      oldval.class.to_s == 'Hash' && newval.class.to_s == 'Hash' ? oldval.deep_merge(newval) : newval
    end
  end
   
end

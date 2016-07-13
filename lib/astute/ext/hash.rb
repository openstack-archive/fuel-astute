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

  def absent_keys(array)
    array.select { |key| self[key].blank? }
  end

  def force_encoding!(encoding, &block)
    each do |key, value|
      case value
        when String
          if block_given?
            self[key] = yield(value.force_encoding(encoding))
          else
            self[key] = value.force_encoding(encoding)
          end
        when Hash then value.force_encoding!(encoding, &block)
      end
    end
  end

end

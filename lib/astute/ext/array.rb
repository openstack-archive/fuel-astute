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


class Array

  def compact_blank
    reject do |val|
      case val
        when Hash   then val.compact_blank.blank?
        when Array  then val.map { |v| v.respond_to?(:compact_blank) ? v.compact_blank : v }.blank?
        when String then val.blank?
        else val.blank?
      end
    end
  end
end

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

require 'kwalify'

module Astute
  module Cli
    class YamlValidator < Kwalify::Validator
    
      def initialize
        gem_path =  Gem.loaded_specs['astute'].full_gem_path
        schema_path = File.join(gem_path, 'lib', 'astute', 'cli', 'schema.yaml')
        @schema = Kwalify::Yaml.load_file(schema_path)
        super(@schema)
      end
    
    # hook method called by Validator#validate()
      def validate_hook(value, rule, path, errors)
        # case rule.name
  #       when 'use_for_provision'
  #         if value['name'] == 'bad'
  #           reason = value['reason']
  #           if !reason || reason.empty?
  #             msg = "reason is required when answer is 'bad'."
  #             errors << Kwalify::ValidationError.new(msg, path)
  #           end
  #         end
  #       end
      end
    end
  end
end
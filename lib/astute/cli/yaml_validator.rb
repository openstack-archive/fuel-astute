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

CIDR_REGEXP = '^(([0-9]|[1-9][0-9]|1[0-9]{2}|2[0-4][0-9]|25[0-5])\.){3}([0-9]|[1-9][0-9]|1[0-9]{2}|
              2[0-4][0-9]|25[0-5])(\/(\d|[1-2]\d|3[0-2]))$'

module Astute
  module Cli
    class YamlValidator < Kwalify::Validator
    
      def initialize(operation)
        schemas = if [:deploy, :provision].include? operation
          [operation]
        elsif operation == :provision_and_deploy
          [:provision, :deploy]
        else
          raise "Incorrect scheme for validation"
        end
        
        schema_hashes = []
        schema_dir_path = File.expand_path(File.dirname(__FILE__)) 
        schemas.each do |schema_name|
          schema_path = File.join(schema_dir_path, "#{schema_name}_schema.yaml")
          schema_hashes << YAML.load_file(schema_path)
        end
        
        #FIXME: key 'hostname:' is undefined for provision_and_deploy. Why?
        @schema = schema_hashes.size == 1 ? schema_hashes.first : schema_hashes[0].deep_merge(schema_hashes[1])
        super(@schema)
      end
    
      # hook method called by Validator#validate()
      def validate_hook(value, rule, path, errors)
        case rule.name
        when 'Attributes'
          require_field(value, path, errors, 'quantum', true, 'quantum_parameters')
          require_field(value, path, errors, 'quantum', true, 'fixed_network_range')
          require_field(value, path, errors, 'quantum', true, 'quantum_access')
          #require_field(value, path, errors, 'quantum', false, 'floating_network_range')
          floating_network_range = value['floating_network_range']
          quantum = value['quantum']
          if quantum
            cidr = Regexp.new(CIDR_REGEXP)
            if cidr.match(floating_network_range).nil?
              msg = "'floating_network_range' is required CIDR notation when quantum is 'true'"
              errors << Kwalify::ValidationError.new(msg, path)
            end
          elsif !floating_network_range.is_a?(Array)
            msg = "'floating_network_range' is required array of IPs when quantum is 'false'"
            errors << Kwalify::ValidationError.new(msg, path)
          end
        when 'Nodes'
          #require_field(value, path, errors, 'quantum', true, 'public_br')
          #require_field(value, path, errors, 'quantum', true, 'internal_br')
        end
      end
      
      private
        
      def require_field(value, path, errors, condition_key, condition_value, key)
        return if value[condition_key] != condition_value
        field_value = value[key]
        if field_value.nil? || field_value.empty?
          msg = "#{key} is required when #{condition_key} is '#{condition_value}'"
          errors << Kwalify::ValidationError.new(msg, path)
        end
      end
      
    end # YamlValidator
  end # Cli
end # Astute
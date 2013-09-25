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
    
      def initialize(operation)
        [:provision].include?(operation) ? schemas = [operation] : raise("Incorrect scheme for validation")
        
        schema_hashes = []
        schema_dir_path = File.expand_path(File.dirname(__FILE__))
        
        schemas.each do |schema_name|
          schema_path = File.join(schema_dir_path, "#{schema_name}_schema.yaml")
          schema_hashes << YAML.load_file(schema_path)
        end
        
        #p schema_hashes[0].recursive_merge!(schema_hashes[1])
        #FIXME: key 'hostname:' is undefined for provision_and_deploy. Why?
        @schema = schema_hashes.size == 1 ? schema_hashes.first : schema_hashes[0].deep_merge(schema_hashes[1])
        super(@schema)
      end
      
    end # YamlValidator
  end # Cli
end # Astute

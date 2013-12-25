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

VALIDATION_SCHEMAS=[:provision]

module Astute
  class Validator < Kwalify::Validator

    def initialize(operation)
      raise("Incorrect scheme for validation: #{operation}") unless VALIDATION_SCHEMAS.include?(operation)

      schema_dir_path = File.expand_path(File.dirname(__FILE__))
      schema_path = File.join(schema_dir_path, 'validation_schemas', "#{operation}_schema.yaml")

      schema_hash = YAML.load_file(schema_path)

      super(schema_hash)
    end

    def validate_data(data, do_raise = true)
      errors = validate(data)
      inspect_errors(errors, do_raise)
    end

    private

    def inspect_errors(errors, do_raise = true)
      errors.each do |e|
        if e.message.include?("is undefined")
          Astute.logger.warn "[#{e.path}] #{e.message}"
        else
          Astute.logger.error "[#{e.path}] #{e.message}"
        end
      end

      if errors.select {|e| !e.message.include?("is undefined") }.size > 0
        raise ValidationError, "Data validation failed" if do_raise
      end
    end

  end

  class ValidationError < StandardError; end
end
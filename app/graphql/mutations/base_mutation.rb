# frozen_string_literal: true

module Mutations
  class BaseMutation < GraphQL::Schema::RelayClassicMutation
    include Authenticatable

    argument_class Types::BaseArgument
    field_class Types::BaseField
    input_object_class Types::BaseInputObject
    object_class Types::BaseObject

    def ready?(**_args)
      current_user!
      true
    end

    private
    def user_errors_from(record)
      record.errors.map do |error|
        {
          message: error.full_message,
          path: [ "input", error.attribute.to_s.camelize(:lower) ],
          code: "VALIDATION_FAILED"
        }
      end
    end
  end
end

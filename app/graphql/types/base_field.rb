# frozen_string_literal: true

module Types
  class BaseField < GraphQL::Schema::Field
    argument_class Types::BaseArgument

    LIST_COMPLEXITY = ->(_ctx, _args, child_complexity) { 10 * child_complexity + 1 }
  end
end

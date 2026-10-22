# frozen_string_literal: true

class CaresyncApiSchema < GraphQL::Schema
  rescue_from(ActiveRecord::RecordNotFound) do |err, _obj, _args, _ctx, _field|
    raise GraphQL::ExecutionError.new(
      "#{err.model || 'Record'} not found",
      extensions: { code: "NOT_FOUND" }
    )
  end

  mutation(Types::MutationType)
  query(Types::QueryType)

  # For batch-loading (see https://graphql-ruby.org/dataloader/overview.html)
  use GraphQL::Dataloader

  # GraphQL-Ruby calls this when something goes wrong while running a query:
  def self.type_error(err, context)
    # if err.is_a?(GraphQL::InvalidNullError)
    #   # report to your bug tracker here
    #   return nil
    # end
    super
  end

  # Limit the depth and size of incoming queries:
  max_depth(8)
  max_complexity(200)
  max_query_string_tokens(5000)
  disable_introspection_entry_points if Rails.env.production?

  # Stop validating when it encounters this many errors:
  validate_max_errors(100)
end

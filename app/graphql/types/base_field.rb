# frozen_string_literal: true

module Types
  class BaseField < GraphQL::Schema::Field
    argument_class Types::BaseArgument

    LIST_COMPLEXITY = ->(_ctx, _args, child_complexity) { 10 * child_complexity + 1 }

    # For a paged list: the cost grows with the requested page size. An out-of-range perPage is clamped here only so
    # it reaches the resolver, which rejects it with a clear INVALID_ARGUMENT error instead of a complexity error.
    PAGE_COMPLEXITY = ->(_ctx, args, child_complexity) { args[:per_page].to_i.clamp(1, Paginator::MAX_PER_PAGE) * child_complexity + 1 }
  end
end

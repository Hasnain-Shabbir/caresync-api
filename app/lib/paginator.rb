# frozen_string_literal: true

# Turns an already tenant-scoped, already ordered relation into one page.
# Callers own tenancy, authorization, search and order. Kaminari does the paging math; this adds our limits and the
# GraphQL page shape.
class Paginator
  # Keep this low enough that a normal page fits under max_complexity (see Types::BaseField::PAGE_COMPLEXITY).
  MAX_PER_PAGE = 30

  def self.call(scope, page:, per_page:)
    validate!(page, per_page)
    records = scope.page(page).per(per_page) # Kaminari does the limit, offset and count

    {
      nodes: records,
      total_count: records.total_count,
      total_pages: records.total_pages,
      page: page,
      per_page: per_page,
      has_next_page: records.next_page.present?,
      has_previous_page: records.prev_page.present?
    }
  end

  def self.validate!(page, per_page)
    invalid("page must be 1 or more") if page < 1
    invalid("perPage must be between 1 and #{MAX_PER_PAGE}") unless per_page.between?(1, MAX_PER_PAGE)
  end

  def self.invalid(message)
    raise GraphQL::ExecutionError.new(message, extensions: { code: "INVALID_ARGUMENT" })
  end
  private_class_method :validate!, :invalid
end

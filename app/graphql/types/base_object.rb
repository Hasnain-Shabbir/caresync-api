# frozen_string_literal: true

module Types
  class BaseObject < GraphQL::Schema::Object
    include Authenticatable

    edge_type_class(Types::BaseEdge)
    connection_type_class(Types::BaseConnection)
    field_class Types::BaseField

    # A list field that always comes as a page: page + perPage arguments, a cost that grows with perPage, and a page
    # type as the result. Every list of records in the schema uses this, so a client can never ask for an unbounded
    # list. Pass a block to add more arguments (for example orderBy). Resolve it with Paginator.call.
    def self.paginated_field(name, page_type, **options, &block)
      field(name, page_type, null: false, complexity: Types::BaseField::PAGE_COMPLEXITY, **options) do
        argument :page, Integer, required: true, default_value: 1
        argument :per_page, Integer, required: true, default_value: 25
        instance_eval(&block) if block
      end
    end
  end
end

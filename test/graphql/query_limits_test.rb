require "test_helper"

# Depth and complexity limits. The limit errors come from validation, so they appear before anything runs.
class QueryLimitsTest < ActiveSupport::TestCase
  REALISTIC = [
    "{ organizations { id name patientsCount } }",
    "{ patients { totalCount totalPages patients { id firstName lastName dateOfBirth } } }"
  ].freeze

  # The real schema has no list cycle any more (schema_shape_test.rb keeps it that way), so the depth and cost limits
  # are tested on a small cyclic schema built here. It reads the real limits, so it cannot drift from them.
  class CyclicNode < GraphQL::Schema::Object
    field_class Types::BaseField
    field :id, ID, null: false
    field :children, [ "QueryLimitsTest::CyclicNode" ], null: false, complexity: Types::BaseField::LIST_COMPLEXITY
  end

  class CyclicQuery < GraphQL::Schema::Object
    field_class Types::BaseField
    field :nodes, [ CyclicNode ], null: false, complexity: Types::BaseField::LIST_COMPLEXITY

    def nodes = []
  end

  CyclicSchema = Class.new(GraphQL::Schema) do
    query CyclicQuery
    max_depth CaresyncApiSchema.max_depth, count_introspection_fields: false
    max_complexity CaresyncApiSchema.max_complexity, count_introspection_fields: false
  end

  # nodes -> children -> children ... repeated `count` times. Each level multiplies the cost.
  def trips(count)
    inner = "id"
    count.times { inner = "children { #{inner} }" }
    "{ nodes { #{inner} } }"
  end

  def error_messages(query, schema: CyclicSchema)
    (schema.execute(query, context: graphql_context, root_value: nil).to_h["errors"] || []).map { |e| e["message"] }
  end

  test "one level of a cyclic list is allowed" do
    assert_empty error_messages(trips(1))
  end

  test "two levels of a cyclic list are rejected for complexity" do
    assert_match(/exceeds max complexity/, error_messages(trips(2)).join)
  end

  test "a deep cyclic query is rejected for depth" do
    assert_match(/exceeds max depth/, error_messages(trips(8)).join)
  end

  test "realistic queries are not rejected (guards against limits that are too tight)" do
    REALISTIC.each do |query|
      result = CaresyncApiSchema.execute(query, context: graphql_context).to_h

      assert_nil result["errors"], "#{query} -> #{result['errors'].inspect}"
    end
  end

  # The real cycle: organization -> patients (a page) -> patient -> organization -> patients ...
  def real_trips(count, page_args: "")
    inner = "id"
    count.times { inner = "patients#{page_args} { patients { organization { #{inner} } } }" }
    "{ organizations { #{inner} } }"
  end

  test "the real cycle: one trip is allowed, two trips are rejected for complexity" do
    assert_nil CaresyncApiSchema.execute(real_trips(1), context: graphql_context).to_h["errors"]

    messages = error_messages(real_trips(2), schema: CaresyncApiSchema)
    assert_match(/exceeds max complexity/, messages.join)
  end

  test "the real cycle with tiny pages is still stopped, by the depth limit" do
    five = real_trips(5, page_args: "(perPage: 1)")

    assert_match(/exceeds max depth/, error_messages(five, schema: CaresyncApiSchema).join)
  end

  test "every list field of objects has a complexity multiplier" do
    # a tenant always sees exactly one organization; the page field (Query.patients) carries the per-page cost
    exempt = %w[Query.organizations PatientPage.patients]
    missing = CaresyncApiSchema.types.values
      .select { |t| t.kind.object? && !t.graphql_name.start_with?("__") && !t.graphql_name.end_with?("Payload") }
      .flat_map { |t| t.fields.values }
      .select { |f| f.type.list? && f.type.unwrap.kind.object? && !f.connection? }
      .reject { |f| f.complexity.is_a?(Proc) || exempt.include?(f.path) }
      .map(&:path)

    assert_empty missing, "Add complexity: Types::BaseField::LIST_COMPLEXITY to: #{missing.join(', ')}"
  end

  # Tests the mechanism only: the real setting is on in production, and this test env keeps introspection on.
  test "disable_introspection_entry_points makes __schema fail" do
    schema = Class.new(CaresyncApiSchema) { disable_introspection_entry_points }
    errors = schema.execute("{ __schema { types { name } } }").to_h["errors"]

    assert_match(/Field '__schema' doesn't exist/, errors.first["message"])
    assert_nil CaresyncApiSchema.execute("{ __schema { queryType { name } } }").to_h["errors"]
  end
end

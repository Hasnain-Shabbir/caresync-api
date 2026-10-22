require "test_helper"

# Depth and complexity limits. The limit errors come from validation, so they appear before anything runs.
class QueryLimitsTest < ActiveSupport::TestCase
  REALISTIC = "{ organizations { id name patients { id firstName lastName dateOfBirth } } }".freeze

  # organizations -> patients -> organization -> ... repeated `count` times. Each trip multiplies the cost.
  def trips(count)
    inner = "id"
    count.times { inner = "patients { organization { #{inner} } }" }
    "{ organizations { #{inner} } }"
  end

  def error_messages(query)
    (CaresyncApiSchema.execute(query, context: graphql_context).to_h["errors"] || []).map { |e| e["message"] }
  end

  test "one trip around the organization/patients cycle is allowed (complexity 22)" do
    assert_empty error_messages(trips(1))
  end

  test "two trips are rejected for complexity (222)" do
    assert_match(/exceeds max complexity/, error_messages(trips(2)).join)
  end

  test "four trips are rejected for depth (10)" do
    assert_match(/exceeds max depth/, error_messages(trips(4)).join)
  end

  test "a realistic query is not rejected (guards against limits that are too tight)" do
    result = CaresyncApiSchema.execute(REALISTIC, context: graphql_context).to_h

    assert_nil result["errors"], result["errors"].inspect
    assert_equal "Sunrise Clinic", result.dig("data", "organizations", 0, "name")
  end

  test "every list field of objects has a complexity multiplier" do
    exempt = %w[Query.organizations] # a tenant always sees exactly one organization
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

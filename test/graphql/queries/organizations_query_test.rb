require "test_helper"

class OrganizationsQueryTest < ActiveSupport::TestCase
  def execute(query, variables: {})
    CaresyncApiSchema.execute(query, variables: variables, context: graphql_context).to_h
  end

  test "organizations returns only the logged-in user's organization" do
    result = execute("{ organizations { id name } }")

    assert_nil result["errors"]
    names = result.dig("data", "organizations").map { |o| o["name"] }
    assert_equal [ "Sunrise Clinic" ], names
  end

  test "organization returns one by id" do
    org = organizations(:sunrise)
    result = execute("query($id: ID!) { organization(id: $id) { id name } }", variables: { id: org.id.to_s })

    assert_nil result["errors"]
    assert_equal({ "id" => org.id.to_s, "name" => "Sunrise Clinic" }, result.dig("data", "organization"))
  end

  test "organization returns null and a NOT_FOUND error for an unknown id" do
    result = execute("query($id: ID!) { organization(id: $id) { id } }", variables: { id: "0" })

    assert_nil result.dig("data", "organization")
    error = result["errors"].first
    assert_equal "Organization not found", error["message"]
    assert_equal "NOT_FOUND", error.dig("extensions", "code")
  end

  test "organization exposes its patient count, not a patient list" do
    org = organizations(:sunrise)
    result = execute("query($id: ID!) { organization(id: $id) { patientsCount } }", variables: { id: org.id.to_s })

    assert_nil result["errors"]
    assert_equal 2, result.dig("data", "organization", "patientsCount")
  end

  test "organization exposes one page of its patients" do
    result = execute("{ organizations { patients(perPage: 1) { totalCount totalPages hasNextPage patients { firstName dateOfBirth } } } }")

    page = result.dig("data", "organizations", 0, "patients")
    assert_nil result["errors"]
    assert_equal 2, page["totalCount"]
    assert_equal 2, page["totalPages"]
    assert page["hasNextPage"]
    assert_equal [ "Alice" ], page["patients"].map { |p| p["firstName"] }
  end

  test "organization patients enforce the same page size limit" do
    result = execute("{ organizations { patients(perPage: 31) { totalCount } } }")

    assert_equal "INVALID_ARGUMENT", result["errors"].first.dig("extensions", "code")
  end

  test "asking for a field that does not exist is a validation error" do
    result = execute("{ organizations { nope } }")

    assert_nil result["data"]
    assert_match(/doesn't exist/, result["errors"].first["message"])
  end
end

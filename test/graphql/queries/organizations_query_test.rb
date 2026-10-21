require "test_helper"

class OrganizationsQueryTest < ActiveSupport::TestCase
  def execute(query, variables: {})
    CaresyncApiSchema.execute(query, variables: variables, context: graphql_context).to_h
  end

  test "organizations returns all organizations ordered by name" do
    result = execute("{ organizations { id name } }")

    assert_nil result["errors"]
    names = result.dig("data", "organizations").map { |o| o["name"] }
    assert_equal [ "Sunrise Clinic", "Valley Health" ], names
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

  test "organization exposes its patients" do
    org = organizations(:sunrise)
    result = execute("query($id: ID!) { organization(id: $id) { patients { firstName lastName dateOfBirth } } }",
                     variables: { id: org.id.to_s })

    patients = result.dig("data", "organization", "patients")
    assert_equal %w[Alice Bob], patients.map { |p| p["firstName"] }.sort
    assert_equal "1990-04-12", patients.find { |p| p["firstName"] == "Alice" }["dateOfBirth"]
  end

  test "asking for a field that does not exist is a validation error" do
    result = execute("{ organizations { nope } }")

    assert_nil result["data"]
    assert_match(/doesn't exist/, result["errors"].first["message"])
  end
end

require "test_helper"

class OrganizationMutationsTest < ActiveSupport::TestCase
  UPDATE = <<~GQL
    mutation($input: UpdateOrganizationInput!) {
      updateOrganization(input: $input) {
        organization { id name }
        errors { message path code }
      }
    }
  GQL

  def execute(query, input)
    CaresyncApiSchema.execute(query, variables: { input: input }, context: graphql_context).to_h
  end

  # Creating and deleting organizations are platform tasks (console, seeds, an internal tool),
  # not something a clinic user can do through the API.
  test "creating and deleting organizations are not part of the API" do
    mutations = CaresyncApiSchema.mutation.fields.keys

    assert_not_includes mutations, "createOrganization"
    assert_not_includes mutations, "deleteOrganization"
  end

  # updateOrganization

  test "update changes the name" do
    org = organizations(:sunrise)
    result = execute(UPDATE, { id: org.id.to_s, name: "Sunrise Clinic Group" })

    payload = result.dig("data", "updateOrganization")
    assert_equal [], payload["errors"]
    assert_equal "Sunrise Clinic Group", payload.dig("organization", "name")
    assert_equal "Sunrise Clinic Group", org.reload.name
  end

  test "update returns a validation error for a blank name and leaves the record unchanged" do
    org = organizations(:sunrise)
    result = execute(UPDATE, { id: org.id.to_s, name: "" })

    payload = result.dig("data", "updateOrganization")
    assert_nil payload["organization"]
    assert_equal "VALIDATION_FAILED", payload["errors"].first["code"]
    assert_equal "Sunrise Clinic", org.reload.name
  end

  test "update with an unknown id returns a top-level NOT_FOUND error" do
    result = execute(UPDATE, { id: "0", name: "Nope" })

    assert_nil result.dig("data", "updateOrganization")
    error = result["errors"].first
    assert_equal "Organization not found", error["message"]
    assert_equal "NOT_FOUND", error.dig("extensions", "code")
  end
end

require "test_helper"

class OrganizationMutationsTest < ActiveSupport::TestCase
  CREATE = <<~GQL
    mutation($input: CreateOrganizationInput!) {
      createOrganization(input: $input) {
        organization { id name }
        errors { message path code }
      }
    }
  GQL

  UPDATE = <<~GQL
    mutation($input: UpdateOrganizationInput!) {
      updateOrganization(input: $input) {
        organization { id name }
        errors { message path code }
      }
    }
  GQL

  DELETE = <<~GQL
    mutation($input: DeleteOrganizationInput!) {
      deleteOrganization(input: $input) {
        deletedId
        errors { message path code }
      }
    }
  GQL

  def execute(query, input)
    CaresyncApiSchema.execute(query, variables: { input: input }, context: graphql_context).to_h
  end

  # createOrganization

  test "create succeeds with a valid name" do
    result = nil
    assert_difference("Organization.count", 1) do
      result = execute(CREATE, { name: "Acme Care" })
    end

    payload = result.dig("data", "createOrganization")
    assert_equal [], payload["errors"]
    assert_equal "Acme Care", payload.dig("organization", "name")
    assert payload.dig("organization", "id").present?
  end

  test "create returns a validation error for a blank name" do
    result = nil
    assert_no_difference("Organization.count") do
      result = execute(CREATE, { name: "" })
    end

    payload = result.dig("data", "createOrganization")
    assert_nil payload["organization"]
    error = payload["errors"].first
    assert_equal "VALIDATION_FAILED", error["code"]
    assert_equal [ "input", "name" ], error["path"]
    assert_match(/can't be blank/, error["message"])
  end

  test "create returns a validation error for a duplicate name" do
    result = nil
    assert_no_difference("Organization.count") do
      result = execute(CREATE, { name: organizations(:sunrise).name })
    end

    error = result.dig("data", "createOrganization", "errors").first
    assert_equal "VALIDATION_FAILED", error["code"]
    assert_match(/has already been taken/, error["message"])
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

  # deleteOrganization

  test "delete removes an organization that has no users or patients" do
    org = Organization.create!(name: "Empty Clinic")
    result = nil
    assert_difference("Organization.count", -1) do
      result = execute(DELETE, { id: org.id.to_s })
    end

    payload = result.dig("data", "deleteOrganization")
    assert_equal [], payload["errors"]
    assert_equal org.id.to_s, payload["deletedId"]
  end

  test "delete returns a CONFLICT error when the organization still has patients or users" do
    result = nil
    assert_no_difference("Organization.count") do
      result = execute(DELETE, { id: organizations(:sunrise).id.to_s })
    end

    payload = result.dig("data", "deleteOrganization")
    assert_nil payload["deletedId"]
    assert_equal "CONFLICT", payload["errors"].first["code"]
  end

  test "delete with an unknown id returns a top-level NOT_FOUND error" do
    result = execute(DELETE, { id: "0" })

    assert_nil result.dig("data", "deleteOrganization")
    assert_equal "NOT_FOUND", result["errors"].first.dig("extensions", "code")
  end
end

require "test_helper"

class Api::V1::OrganizationsControllerTest < ActionDispatch::IntegrationTest
  test "index returns all organizations as JSON" do
    get api_v1_organizations_url, as: :json

    assert_response :success
    body = response.parsed_body
    assert_equal Organization.count, body.size
    assert_equal [ "Sunrise Clinic", "Valley Health" ], body.map { |o| o["name"] }
  end

  test "show returns the organization as JSON" do
    organization = organizations(:sunrise)

    get api_v1_organization_url(organization), as: :json

    assert_response :success
    body = response.parsed_body
    assert_equal organization.id, body["id"]
    assert_equal "Sunrise Clinic", body["name"]
  end

  test "show returns a 404 error envelope when the organization does not exist" do
    get api_v1_organization_url(id: 0), as: :json

    assert_response :not_found
    error = response.parsed_body["error"]
    assert_equal "not_found", error["code"]
    assert_equal "Organization not found", error["message"]
  end

  test "create adds an organization and returns 201" do
    assert_difference("Organization.count", 1) do
      post api_v1_organizations_url, params: { organization: { name: "New Clinic" } }, as: :json
    end

    assert_response :created
    assert_equal "New Clinic", response.parsed_body["name"]
  end

  test "create with a duplicate name returns 422" do
    assert_no_difference("Organization.count") do
      post api_v1_organizations_url, params: { organization: { name: "Sunrise Clinic" } }, as: :json
    end

    assert_response :unprocessable_content
    error = response.parsed_body["error"]
    assert_equal "validation_failed", error["code"]
    assert error["details"].key?("name")
  end

  test "create without the organization key returns 400" do
    assert_no_difference("Organization.count") do
      post api_v1_organizations_url, params: {}, as: :json
    end

    assert_response :bad_request
    assert_equal "bad_request", response.parsed_body["error"]["code"]
  end

  test "update changes the organization name and returns 200" do
    organization = organizations(:sunrise)

    patch api_v1_organization_url(organization), params: { organization: { name: "Renamed Clinic" } }, as: :json

    assert_response :success
    assert_equal "Renamed Clinic", response.parsed_body["name"]
    assert_equal "Renamed Clinic", organization.reload.name
  end

  test "update with a duplicate name returns 422 and does not change the name" do
    organization = organizations(:sunrise)

    patch api_v1_organization_url(organization), params: { organization: { name: "Valley Health" } }, as: :json

    assert_response :unprocessable_content
    assert_equal "validation_failed", response.parsed_body["error"]["code"]
    assert_equal "Sunrise Clinic", organization.reload.name
  end

  test "update returns 404 when the organization does not exist" do
    patch api_v1_organization_url(id: 0), params: { organization: { name: "Nope" } }, as: :json

    assert_response :not_found
    assert_equal "not_found", response.parsed_body["error"]["code"]
  end

  test "destroy removes the organization and returns 204" do
    organization = organizations(:valley)

    assert_difference("Organization.count", -1) do
      delete api_v1_organization_url(organization), as: :json
    end

    assert_response :no_content
    assert_empty response.body
  end

  test "destroy returns 404 when the organization does not exist" do
    assert_no_difference("Organization.count") do
      delete api_v1_organization_url(id: 0), as: :json
    end

    assert_response :not_found
  end

  test "destroy returns 409 when the organization still has users or patients" do
    assert_no_difference("Organization.count") do
      delete api_v1_organization_url(organizations(:sunrise)), as: :json
    end

    assert_response :conflict
    assert_equal "conflict", response.parsed_body["error"]["code"]
  end
end

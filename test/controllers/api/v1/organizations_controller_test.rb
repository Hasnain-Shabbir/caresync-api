require "test_helper"

class Api::V1::OrganizationsControllerTest < ActionDispatch::IntegrationTest
  test "index returns all organizations as JSON" do
    get api_v1_organizations_url, as: :json

    assert_response :success
    body = response.parsed_body
    assert_equal Organization.count, body.size
    assert_equal ["Sunrise Clinic", "Valley Health"], body.map { |o| o["name"] }
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
end

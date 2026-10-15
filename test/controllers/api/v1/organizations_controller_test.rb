require "test_helper"

class Api::V1::OrganizationsControllerTest < ActionDispatch::IntegrationTest
  test "index returns all organizations as JSON" do
    get api_v1_organizations_url, as: :json

    assert_response :success
    body = response.parsed_body
    assert_equal Organization.count, body.size
    assert_equal ["Sunrise Clinic", "Valley Health"], body.map { |o| o["name"] }
  end
end

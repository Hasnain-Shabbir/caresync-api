require "test_helper"

class GraphqlControllerTest < ActionDispatch::IntegrationTest
  test "POST /graphql runs a query and returns JSON" do
    post graphql_url, params: { query: "{ organizations { name } }" }, as: :json, headers: auth_headers

    assert_response :success
    names = response.parsed_body.dig("data", "organizations").map { |o| o["name"] }
    assert_equal [ "Sunrise Clinic", "Valley Health" ], names
  end

  test "variables are passed through" do
    org = organizations(:valley)
    post graphql_url,
         params: { query: "query($id: ID!) { organization(id: $id) { name } }", variables: { id: org.id.to_s } },
         as: :json,
         headers: auth_headers

    assert_response :success
    assert_equal "Valley Health", response.parsed_body.dig("data", "organization", "name")
  end

  test "an invalid query returns HTTP 200 with an errors array" do
    post graphql_url, params: { query: "{ nope }" }, as: :json, headers: auth_headers

    assert_response :success
    assert response.parsed_body["errors"].present?
  end
end

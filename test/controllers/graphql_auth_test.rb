require "test_helper"

# Request-level authentication tests: a real Bearer token travels through Warden and the allowlist.
class GraphqlAuthTest < ActionDispatch::IntegrationTest
  ORGANIZATIONS = "{ organizations { name } }".freeze
  LOGIN = <<~GQL.freeze
    mutation($input: LoginInput!) {
      login(input: $input) { token errors { code } }
    }
  GQL
  LOGOUT = "mutation { logout(input: {}) { success } }".freeze

  def gql(query, token: nil, variables: nil)
    headers = token ? { "Authorization" => "Bearer #{token}" } : {}
    post graphql_url, params: { query: query, variables: variables }.compact, as: :json, headers: headers
    response.parsed_body
  end

  def login_token(email = "admin@sunrise.test", password = "password")
    gql(LOGIN, variables: { input: { email: email, password: password } }).dig("data", "login", "token")
  end

  def assert_unauthenticated(body)
    assert_equal "UNAUTHENTICATED", body["errors"]&.first&.dig("extensions", "code"), body.inspect
  end

  test "a request with no Authorization header is rejected" do
    assert_unauthenticated gql(ORGANIZATIONS)
  end

  test "a request with a garbage token is rejected" do
    assert_unauthenticated gql(ORGANIZATIONS, token: "not.a.token")
  end

  test "a request with a header that is not a Bearer token is rejected" do
    post graphql_url, params: { query: ORGANIZATIONS }, as: :json, headers: { "Authorization" => "Basic abc123" }

    assert_unauthenticated response.parsed_body
  end

  test "login works without a token" do
    body = gql(LOGIN, variables: { input: { email: "admin@sunrise.test", password: "password" } })

    assert_equal [], body.dig("data", "login", "errors")
    assert body.dig("data", "login", "token").present?
  end

  test "the token from login is accepted on the next request" do
    token = login_token
    body = gql(ORGANIZATIONS, token: token)

    assert_nil body["errors"]
    assert_equal [ "Sunrise Clinic", "Valley Health" ], body.dig("data", "organizations").map { |o| o["name"] }
  end

  test "logout makes the same token stop working at once" do
    token = login_token
    assert_nil gql(ORGANIZATIONS, token: token)["errors"], "the token should work before logout"

    logout = gql(LOGOUT, token: token)
    assert_equal true, logout.dig("data", "logout", "success")

    assert_unauthenticated gql(ORGANIZATIONS, token: token)
  end

  test "logout removes only that token, other sessions of the same user keep working" do
    first = login_token
    second = login_token

    gql(LOGOUT, token: first)

    assert_unauthenticated gql(ORGANIZATIONS, token: first)
    assert_nil gql(ORGANIZATIONS, token: second)["errors"]
  end

  test "logout without a token is rejected" do
    assert_unauthenticated gql(LOGOUT)
  end

  test "a token is rejected once its allowlist row is gone" do
    token = login_token
    AllowlistedJwt.delete_all

    assert_unauthenticated gql(ORGANIZATIONS, token: token)
  end

  test "a token is rejected after it expires" do
    token = login_token
    assert_nil gql(ORGANIZATIONS, token: token)["errors"]

    travel_to(31.minutes.from_now) do
      assert_unauthenticated gql(ORGANIZATIONS, token: token)
    end
  end

  test "a token is still accepted just before it expires" do
    token = login_token

    travel_to(29.minutes.from_now) do
      assert_nil gql(ORGANIZATIONS, token: token)["errors"]
    end
  end

  test "a locked account cannot log in over HTTP" do
    user = users(:nurse_sunrise)
    5.times { login_token(user.email, "wrong-password") }

    assert_nil login_token(user.email, "password")
  end
end

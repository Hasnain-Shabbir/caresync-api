require "test_helper"

# Rack::Attack throttling on the three anonymous operations. The test env cache is a null store (nothing would
# ever be throttled), so each test swaps in a memory store and puts the null store back afterwards.
class RateLimitTest < ActionDispatch::IntegrationTest
  LOGIN = <<~GQL.freeze
    mutation($input: LoginInput!) {
      login(input: $input) { token errors { code } }
    }
  GQL
  REQUEST_RESET = <<~GQL.freeze
    mutation($input: RequestPasswordResetInput!) {
      requestPasswordReset(input: $input) { success }
    }
  GQL

  setup do
    Rack::Attack.cache.store = ActiveSupport::Cache::MemoryStore.new
    Rack::Attack.reset!
  end

  teardown do
    Rack::Attack.cache.store = Rails.cache
  end

  def gql(query, variables: nil, ip: "10.0.0.1", headers: {})
    post graphql_url, params: { query: query, variables: variables }.compact, as: :json,
         headers: headers, env: { "REMOTE_ADDR" => ip }
  end

  def login_attempt(ip: "10.0.0.1")
    gql(LOGIN, variables: { input: { email: "nobody@sunrise.test", password: "wrong" } }, ip: ip)
  end

  test "the 11th login from one IP within a minute returns 429, the first 10 do not" do
    10.times do
      login_attempt
      assert_response :success
    end

    login_attempt

    assert_response :too_many_requests
    assert_equal "RATE_LIMITED", response.parsed_body.dig("errors", 0, "extensions", "code")
    assert response.headers["Retry-After"].present?
  end

  test "another IP is not affected" do
    11.times { login_attempt }
    assert_response :too_many_requests

    login_attempt(ip: "10.0.0.2")

    assert_response :success
  end

  test "normal queries are never counted" do
    15.times do
      gql("{ organizations { id } }", headers: auth_headers)
      assert_response :success
    end
  end

  test "two aliased logins in one request are rejected" do
    gql('mutation { a: login(input: {email: "x@y.z", password: "1"}) { token } b: login(input: {email: "x@y.z", password: "2"}) { token } }')

    assert_response :forbidden
  end

  test "the 4th password reset request for the same email returns 429, whatever the case and IP" do
    emails = %w[Victim@Example.com victim@example.com VICTIM@example.com victim@example.com]
    statuses = emails.each_with_index.map do |email, i|
      gql(REQUEST_RESET, variables: { input: { email: email } }, ip: "10.1.0.#{i}")
      response.status
    end

    assert_equal [ 200, 200, 200, 429 ], statuses
  end

  test "different emails are not throttled against each other" do
    4.times do |i|
      gql(REQUEST_RESET, variables: { input: { email: "person#{i}@example.com" } }, ip: "10.2.0.#{i}")
      assert_response :success
    end
  end
end

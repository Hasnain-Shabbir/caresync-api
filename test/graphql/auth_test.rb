require "test_helper"

# Schema-level authentication tests (no HTTP): who may call what, and how login behaves.
class AuthTest < ActiveSupport::TestCase
  LOGIN = <<~GQL
    mutation($input: LoginInput!) {
      login(input: $input) {
        token
        user { id email role }
        errors { message path code }
      }
    }
  GQL

  def execute(query, variables: {}, context: {})
    CaresyncApiSchema.execute(query, variables: variables, context: context).to_h
  end

  def login(email, password)
    execute(LOGIN, variables: { input: { email: email, password: password } })
  end

  def assert_unauthenticated(result)
    error = result["errors"]&.first
    assert error, "expected an error but got none: #{result.inspect}"
    assert_equal "UNAUTHENTICATED", error.dig("extensions", "code")
  end

  # Without a logged-in user

  test "organizations query without a user is rejected" do
    assert_unauthenticated execute("{ organizations { name } }")
  end

  test "organization query without a user is rejected" do
    id = organizations(:sunrise).id.to_s
    assert_unauthenticated execute("query($id: ID!) { organization(id: $id) { name } }", variables: { id: id })
  end

  test "patient query without a user is rejected" do
    id = patients(:alice).id.to_s
    assert_unauthenticated execute("query($id: ID!) { patient(id: $id) { firstName } }", variables: { id: id })
  end

  test "a mutation without a user is rejected and creates nothing" do
    mutation = 'mutation { createOrganization(input: { name: "Sneaky Clinic" }) { organization { id } } }'

    assert_no_difference("Organization.count") do
      assert_unauthenticated execute(mutation)
    end
  end

  test "a patient mutation without a user is rejected and changes nothing" do
    patient = patients(:alice)
    mutation = %(mutation { updatePatient(input: { id: "#{patient.id}", firstName: "Hacked" }) { patient { id } } })

    assert_unauthenticated execute(mutation)
    assert_equal "Alice", patient.reload.first_name
  end

  test "with a user the same query works" do
    result = execute("{ organizations { name } }", context: graphql_context)

    assert_nil result["errors"]
    assert_equal [ "Sunrise Clinic", "Valley Health" ], result.dig("data", "organizations").map { |o| o["name"] }
  end

  # login

  test "login with the right password returns a token and writes an allowlist row" do
    result = nil
    assert_difference("AllowlistedJwt.count", 1) do
      result = login("admin@sunrise.test", "password")
    end

    payload = result.dig("data", "login")
    assert_equal [], payload["errors"]
    assert_equal 3, payload["token"].split(".").size, "a JWT has three dot-separated parts"
    assert_equal "admin@sunrise.test", payload.dig("user", "email")
    assert_equal "admin", payload.dig("user", "role")
  end

  test "the stored allowlist entry belongs to the user who logged in" do
    login("admin@sunrise.test", "password")

    assert_equal 1, users(:admin_sunrise).allowlisted_jwts.count
    assert_equal 0, users(:nurse_sunrise).allowlisted_jwts.count
  end

  test "login with a wrong password is rejected and issues no token" do
    result = nil
    assert_no_difference("AllowlistedJwt.count") do
      result = login("admin@sunrise.test", "not-the-password")
    end

    payload = result.dig("data", "login")
    assert_nil payload["token"]
    assert_nil payload["user"]
    assert_equal "INVALID_CREDENTIALS", payload["errors"].first["code"]
  end

  test "login with an unknown email gives the same error as a wrong password" do
    unknown = login("nobody@sunrise.test", "password").dig("data", "login", "errors").first
    wrong = login("admin@sunrise.test", "wrong").dig("data", "login", "errors").first

    assert_equal wrong["message"], unknown["message"]
    assert_equal wrong["code"], unknown["code"]
  end

  test "email is matched without regard to case" do
    result = login("ADMIN@Sunrise.test", "password")

    assert_equal [], result.dig("data", "login", "errors")
  end

  test "five wrong passwords lock the account, and then even the right password is refused" do
    user = users(:nurse_sunrise)

    5.times { login(user.email, "wrong-password") }

    assert user.reload.access_locked?, "the account should be locked after 5 failed attempts"

    result = login(user.email, "password")
    assert_nil result.dig("data", "login", "token")
    assert_equal "INVALID_CREDENTIALS", result.dig("data", "login", "errors").first["code"]
  end

  test "a locked account gets the same error as a wrong password" do
    user = users(:nurse_sunrise)
    5.times { login(user.email, "wrong-password") }

    locked = login(user.email, "password").dig("data", "login", "errors").first
    wrong = login("admin@sunrise.test", "wrong").dig("data", "login", "errors").first

    assert_equal wrong["message"], locked["message"]
  end

  test "deleting a user deletes their allowlisted tokens" do
    user = users(:admin_sunrise)
    login(user.email, "password")
    assert_operator user.allowlisted_jwts.count, :>=, 1

    assert_difference("AllowlistedJwt.count", -user.allowlisted_jwts.count) do
      user.destroy!
    end
  end
end

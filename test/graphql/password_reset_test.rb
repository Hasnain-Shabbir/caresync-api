require "test_helper"

# Password reset: requestPasswordReset (background email) and resetPassword (token to new password).
class PasswordResetTest < ActiveSupport::TestCase
  include ActionMailer::TestHelper
  include ActiveJob::TestHelper

  REQUEST = <<~GQL
    mutation($input: RequestPasswordResetInput!) {
      requestPasswordReset(input: $input) { success }
    }
  GQL

  RESET = <<~GQL
    mutation($input: ResetPasswordInput!) {
      resetPassword(input: $input) {
        success
        errors { message path code }
      }
    }
  GQL

  LOGIN = <<~GQL
    mutation($input: LoginInput!) {
      login(input: $input) {
        token
        errors { message path code }
      }
    }
  GQL

  NEW_PASSWORD = "NewPassw0rd!"

  def execute(query, variables: {})
    CaresyncApiSchema.execute(query, variables: variables).to_h
  end

  def request_reset(email)
    execute(REQUEST, variables: { input: { email: email } })
  end

  def reset_password(token, password: NEW_PASSWORD, confirmation: password)
    execute(RESET, variables: { input: { token: token, password: password, passwordConfirmation: confirmation } })
  end

  def login(email, password)
    execute(LOGIN, variables: { input: { email: email, password: password } })
  end

  # The raw token (the email normally carries it). Devise stores only a digest.
  def raw_token_for(user)
    clear_enqueued_jobs
    user.send_reset_password_instructions
  end

  # 1

  test "request for a known email enqueues one mail and stores a token digest" do
    user = users(:nurse_sunrise)

    assert_enqueued_emails 1 do
      result = request_reset(user.email)
      assert_equal true, result.dig("data", "requestPasswordReset", "success")
    end

    assert user.reload.reset_password_token.present?
  end

  # 2

  test "request for an unknown email gives the same response and enqueues nothing" do
    known = request_reset(users(:nurse_sunrise).email)

    unknown = nil
    assert_no_enqueued_jobs do
      unknown = request_reset("nobody@sunrise.test")
    end

    assert_equal known, unknown
  end

  # 3

  test "the mail goes to the user, links to the frontend and holds no patient data" do
    user = users(:nurse_sunrise)

    perform_enqueued_jobs { request_reset(user.email) }

    mail = ActionMailer::Base.deliveries.last
    assert_equal [ user.email ], mail.to
    assert_equal "Reset password instructions", mail.subject

    body = mail.body.to_s
    assert_includes body, "/reset-password?token="
    Patient.find_each do |patient|
      refute_includes body, patient.first_name
      refute_includes body, patient.last_name
    end
  end

  # 4

  test "a valid token changes the password" do
    user = users(:nurse_sunrise)
    token = raw_token_for(user)

    result = reset_password(token)

    assert_equal true, result.dig("data", "resetPassword", "success")
    assert_equal [], result.dig("data", "resetPassword", "errors")
    assert user.reload.valid_password?(NEW_PASSWORD)
    refute user.valid_password?("password")
  end

  # 5

  test "a token works only once" do
    token = raw_token_for(users(:nurse_sunrise))

    assert_equal true, reset_password(token).dig("data", "resetPassword", "success")

    second = reset_password(token, password: "AnotherPassw0rd!").dig("data", "resetPassword")
    assert_equal false, second["success"]
    assert_equal "VALIDATION_FAILED", second["errors"].first["code"]
    assert_equal [ "input", "resetPasswordToken" ], second["errors"].first["path"]
  end

  # 6

  test "an expired token is rejected" do
    user = users(:nurse_sunrise)
    token = raw_token_for(user)

    travel 7.hours do
      result = reset_password(token).dig("data", "resetPassword")

      assert_equal false, result["success"]
      assert_equal "VALIDATION_FAILED", result["errors"].first["code"]
    end

    assert user.reload.valid_password?("password")
  end

  # 7

  test "a weak password is rejected and the password stays the same" do
    user = users(:nurse_sunrise)
    token = raw_token_for(user)

    result = reset_password(token, password: "short").dig("data", "resetPassword")

    assert_equal false, result["success"]
    assert_equal "VALIDATION_FAILED", result["errors"].first["code"]
    assert user.reload.valid_password?("password")
  end

  test "a mismatched confirmation is rejected and the password stays the same" do
    user = users(:nurse_sunrise)
    token = raw_token_for(user)

    result = reset_password(token, confirmation: "Different1!").dig("data", "resetPassword")

    assert_equal false, result["success"]
    assert_equal "VALIDATION_FAILED", result["errors"].first["code"]
    assert user.reload.valid_password?("password")
  end

  # 8 (the old JWT check over HTTP is in PasswordResetSessionTest below)

  test "a reset deletes the user's allowlisted tokens and leaves other users alone" do
    user = users(:nurse_sunrise)
    other = users(:admin_sunrise)
    login(user.email, "password")
    login(other.email, "password")
    assert_equal 1, user.allowlisted_jwts.count

    token = raw_token_for(user)
    reset_password(token)

    assert_equal 0, user.allowlisted_jwts.count
    assert_equal 1, other.allowlisted_jwts.count
  end

  # 9

  test "a locked user can log in after a reset" do
    user = users(:nurse_sunrise)
    user.update_columns(locked_at: Time.current, failed_attempts: 5)
    assert user.reload.access_locked?

    token = raw_token_for(user)
    assert_equal true, reset_password(token).dig("data", "resetPassword", "success")

    refute user.reload.access_locked?
    result = login(user.email, NEW_PASSWORD)
    assert_equal [], result.dig("data", "login", "errors")
    assert result.dig("data", "login", "token").present?
  end
end

class PasswordResetSessionTest < ActionDispatch::IntegrationTest
  test "a token issued before a reset stops working after it" do
    user = users(:nurse_sunrise)
    headers = auth_headers(user)

    post "/graphql", params: { query: "{ organizations { name } }" }, headers: headers, as: :json
    assert_nil response.parsed_body["errors"], "the token should work before the reset"

    raw_token = user.send_reset_password_instructions
    mutation = %(mutation { resetPassword(input: { token: "#{raw_token}", password: "NewPassw0rd!", passwordConfirmation: "NewPassw0rd!" }) { success } })
    post "/graphql", params: { query: mutation }, as: :json
    assert_equal true, response.parsed_body.dig("data", "resetPassword", "success")

    post "/graphql", params: { query: "{ organizations { name } }" }, headers: headers, as: :json
    assert_equal "UNAUTHENTICATED", response.parsed_body.dig("errors", 0, "extensions", "code")
  end
end

require "test_helper"

# Secrets must not reach the logs: job arguments (reset token) and credentials written inline in a query.
class LogHygieneTest < ActionDispatch::IntegrationTest
  include ActiveJob::TestHelper

  REQUEST_RESET = <<~GQL.freeze
    mutation($input: RequestPasswordResetInput!) {
      requestPasswordReset(input: $input) { success }
    }
  GQL
  INLINE_LOGIN = 'mutation { login(input: {email: "a@b.c", password: "Secret123!"}) { token } }'.freeze

  # Runs a password reset request and returns [text written by Active Job's logger, raw token from the mail].
  def reset_log_and_token
    io = StringIO.new
    previous = ActiveJob::Base.logger
    ActiveJob::Base.logger = ActiveSupport::Logger.new(io)
    perform_enqueued_jobs do
      CaresyncApiSchema.execute(REQUEST_RESET, variables: { input: { email: users(:nurse_sunrise).email } })
    end
    token = ActionMailer::Base.deliveries.last.body.to_s[/token=([\w-]+)/, 1]
    [ io.string, token ]
  ensure
    ActiveJob::Base.logger = previous
  end

  # Positive control: with argument logging ON the token shows up, so the test below can really fail.
  test "the capture works: with log_arguments on, the token appears in the job log" do
    previous = ActiveJob::Base.log_arguments
    ActiveJob::Base.log_arguments = true
    log, token = reset_log_and_token

    assert token.present?
    assert_includes log, token
  ensure
    ActiveJob::Base.log_arguments = previous
  end

  test "the job log does not contain the reset token" do
    log, token = reset_log_and_token

    assert token.present?
    assert log.present?, "expected Active Job to log something"
    assert_not_includes log, token
  end

  test "credentials written inline in a login query are redacted" do
    post graphql_url, params: { query: INLINE_LOGIN }, as: :json

    assert_equal "[FILTERED]", request.filtered_parameters["query"]
  end

  test "a variables value sent as a string is redacted" do
    post graphql_url, params: { query: "{ __typename }", variables: '{"input":{"password":"Secret123!"}}' }, as: :json

    assert_equal "[FILTERED]", request.filtered_parameters["variables"]
  end

  test "a normal query is not redacted" do
    post graphql_url, params: { query: "{ patients { id } }" }, as: :json, headers: auth_headers

    assert_equal "{ patients { id } }", request.filtered_parameters["query"]
  end
end

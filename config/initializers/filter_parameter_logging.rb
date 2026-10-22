GRAPHQL_AUTH_OPERATION = /\b(login|requestPasswordReset|resetPassword)\b/
# Be sure to restart your server when you modify this file.

# Configure parameters to be partially matched (e.g. passw matches password) and filtered from the log file.
# Use this to limit dissemination of sensitive information.
# See the ActiveSupport::ParameterFilter documentation for supported notations and behaviors.
Rails.application.config.filter_parameters += [
  :passw, :email, :secret, :token, :_key, :crypt, :salt, :certificate, :otp, :ssn, :cvv, :cvc,
  ->(key, value) { value.replace("[FILTERED]") if key == "query" && value.is_a?(String) && value.match?(GRAPHQL_AUTH_OPERATION) },
  ->(key, value) { value.replace("[FILTERED]") if key == "variables" && value.is_a?(String) }
]

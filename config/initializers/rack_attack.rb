class Rack::Attack
  AUTH_OPERATIONS = /\b(login|requestPasswordReset|resetPassword)\b/

  # Parse the GraphQL POST body once per request and remember it in the Rack env.
  def self.graphql_params(req)
    return {} unless req.post? && req.path == "/graphql"

    req.env["caresync.graphql_params"] ||=
      if req.media_type == "application/json"
        body = req.body.read
        req.body.rewind # Rails must still be able to read the body after us
        JSON.parse(body)
      else
        req.POST
      end
  rescue JSON::ParserError
    req.env["caresync.graphql_params"] = {}
  end

  def self.auth_operations(req)
    query = graphql_params(req)["query"]
    query.is_a?(String) ? query.scan(AUTH_OPERATIONS).flatten : []
  end

  # The email inside variables.input (the clients send variables as a JSON object).
  def self.input_email(req)
    variables = graphql_params(req)["variables"]
    email = variables.is_a?(Hash) ? variables.dig("input", "email") : nil
    email.to_s.strip.downcase.presence
  end

  # One HTTP request must not carry several auth operations (aliases would multiply attempts).
  blocklist("graphql/batched-auth") { |req| auth_operations(req).size > 1 }

  # 1. Per IP, for the three operations an anonymous caller can reach.
  throttle("auth/ip", limit: 10, period: 1.minute) do |req|
    req.ip if auth_operations(req).any?
  end

  # 2. Per email, so nobody can flood one person's inbox with reset mails.
  throttle("password-reset/email", limit: 3, period: 1.hour) do |req|
    input_email(req) if auth_operations(req) == [ "requestPasswordReset" ]
  end

  self.throttled_responder = lambda do |req|
    retry_after = (req.env["rack.attack.match_data"] || {})[:period].to_i
    [ 429,
      { "content-type" => "application/json", "retry-after" => retry_after.to_s },
      [ { errors: [ { message: "Too many requests", extensions: { code: "RATE_LIMITED" } } ] }.to_json ] ]
  end
end

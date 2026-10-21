module Mutations
  class Login < BaseMutation
    null true

    argument :email, String, required: true
    argument :password, String, required: true

    field :token, String
    field :user, Types::UserType
    field :errors, [ Types::UserErrorType ], null: false

    # Login is the one mutation that works without a token.
    def ready?(**_args)
      true
    end

    def resolve(email:, password:)
      user = User.find_for_database_authentication(email: email)

      if user&.valid_for_authentication? { user.valid_password?(password) } && user.active_for_authentication?
        token, payload = Warden::JWTAuth::UserEncoder.new.call(user, :user, nil)
        user.on_jwt_dispatch(token, payload) # writes the allowlist row, so the token is accepted later
        { token: token, user: user, errors: [] }
      else
        # One message for unknown email, wrong password and locked account (no user enumeration).
        { token: nil, user: nil, errors: [ { message: "Invalid email or password", path: [ "input" ], code: "INVALID_CREDENTIALS" } ] }
      end
    end
  end
end

module Mutations
  module Auth
    class ResetPassword < BaseMutation
      null true

      argument :token, String, required: true
      argument :password, String, required: true
      argument :password_confirmation, String, required: true

      field :success, Boolean, null: false
      field :errors, [ Types::UserErrorType ], null: false

      # The user has no session yet, so no login is required.
      def ready?(**_args)
        true
      end

      def resolve(token:, password:, password_confirmation:)
        user = User.reset_password_by_token(
          reset_password_token: token,
          password: password,
          password_confirmation: password_confirmation
        )

        if user.errors.empty?
          user.allowlisted_jwts.destroy_all
          user.unlock_access! if user.access_locked?
          { success: true, errors: [] }
        else
          { success: false, errors: user_errors_from(user) }
        end
      end
    end
  end
end

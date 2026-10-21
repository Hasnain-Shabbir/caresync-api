module Mutations
  class RequestPasswordReset < BaseMutation
    null true

    argument :email, String, required: true

    field :success, Boolean, null: false

    # Works without a token, like Login.
    def ready?(**_args)
      true
    end

    def resolve(email:)
      # Ignore the result: an unknown email must look the same as a known one.
      User.send_reset_password_instructions(email: email)
      { success: true }
    end
  end
end

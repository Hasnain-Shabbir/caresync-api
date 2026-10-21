include Authenticatable

module Mutations
  class Logout < BaseMutation
    null true

    field :success, Boolean, null: false

    def resolve
      payload = Warden::JWTAuth::TokenDecoder.new.call(context[:token])
      current_user.allowlisted_jwts.where(jti: payload["jti"]).delete_all
      { success: true }
    end
  end
end

module Types
  class UserErrorType < Types::BaseObject
    field :message, String, null: false
    field :path, [ String ], null: false
    field :code, String, null: false
  end
end

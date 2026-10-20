module Types
  class PatientType < Types::BaseObject
    field :id, ID, null: false
    field :first_name, String, null: false
    field :last_name, String, null: false
    field :date_of_birth, GraphQL::Types::ISO8601Date, null: false
  end
end

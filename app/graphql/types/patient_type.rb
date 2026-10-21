module Types
  class PatientType < Types::BaseObject
    field :id, ID, null: false
    field :first_name, String, null: false
    field :last_name, String, null: false
    field :date_of_birth, GraphQL::Types::ISO8601Date, null: true    # was null: false
    field :organization, Types::OrganizationType, null: false

    def date_of_birth
      object.date_of_birth if Pundit.policy!(current_user!, object).view_date_of_birth?
    end
  end
end

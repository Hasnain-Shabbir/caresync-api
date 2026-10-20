module Types
  class OrganizationType < Types::BaseObject
    field :id, ID, null: false
    field :name, String, null: false
    field :patients, [ Types::PatientType ], null: false
  end
end

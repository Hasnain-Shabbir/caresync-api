module Mutations
  class UpdateOrganization < BaseMutation
    null true

    argument :id, ID, required: true
    argument :name, String, required: true

    field :organization, Types::OrganizationType
    field :errors, [ Types::UserErrorType ], null: false

    def resolve(id:, name:)
      organization = Organization.where(id: current_organization.id).find(id)

      if organization.update(name: name)
        { organization: organization, errors: [] }
      else
        { organization: nil, errors: user_errors_from(organization) }
      end
    end
  end
end

module Mutations
  class CreateOrganization < BaseMutation
    null true

    argument :name, String, required: true

    field :organization, Types::OrganizationType
    field :errors, [ Types::UserErrorType ], null: false

    def resolve(name:)
      organization = Organization.new(name: name)

      if organization.save
        { organization: organization, errors: [] }
      else
        { organization: nil, errors: user_errors_from(organization) }
      end
    end
  end
end

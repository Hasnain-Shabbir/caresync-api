module Mutations
  module Organizations
    class UpdateOrganization < BaseMutation
      null true

      argument :id, ID, required: true
      argument :name, String, required: true

      field :organization, Types::OrganizationType
      field :errors, [ Types::UserErrorType ], null: false

      def resolve(id:, name:)
        organization = Organization.where(id: current_organization.id).find(id)
        authorize!(organization, :update?)

        result = ::Organizations::Update.call(organization: organization, attributes: { name: name })

        if result.success?
          { organization: result.value, errors: [] }
        else
          { organization: nil, errors: user_errors_from(result.value) }
        end
      end
    end
  end
end

module Mutations
  class DeleteOrganization < BaseMutation
    null true

    argument :id, ID, required: true

    field :deleted_id, ID
    field :errors, [ Types::UserErrorType ], null: false

    def resolve(id:)
      organization = Organization.find(id)
      organization.destroy!
      { deleted_id: id, errors: [] }
    rescue ActiveRecord::DeleteRestrictionError
      {
        deleted_id: nil,
        errors: [ {
          message: "Cannot delete an organization that still has users or patients",
          path: [ "input", "id" ],
          code: "CONFLICT"
        } ]
      }
    end
  end
end

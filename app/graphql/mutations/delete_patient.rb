module Mutations
  class DeletePatient < BaseMutation
    null true

    argument :id, ID, required: true

    # Return type: graphql-ruby generates DeletePatientPayload from these two fields.
    field :deleted_id, ID
    field :errors, [ Types::UserErrorType ], null: false

    def resolve(id:)
      patient = Patient.find(id)
      patient.destroy!

      { deleted_id: id, errors: [] }
    end
  end
end

module Mutations
  module Patients
    class DeletePatient < BaseMutation
      null true

      argument :id, ID, required: true

      # Return type: graphql-ruby generates DeletePatientPayload from these two fields.
      field :deleted_id, ID
      field :errors, [ Types::UserErrorType ], null: false

      def resolve(id:)
        patient = current_organization.patients.find(id)
        authorize!(patient, :destroy?)
        ::Patients::Destroy.call(patient: patient)

        { deleted_id: id, errors: [] }
      end
    end
  end
end

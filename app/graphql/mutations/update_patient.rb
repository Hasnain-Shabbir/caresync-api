module Mutations
  class UpdatePatient < BaseMutation
    null true

    argument :id, ID, required: true
    argument :first_name, String, required: false
    argument :last_name, String, required: false
    argument :date_of_birth, GraphQL::Types::ISO8601Date, required: false

    # Return type: graphql-ruby generates UpdatePatientPayload from these two fields.
    field :patient, Types::PatientType
    field :errors, [ Types::UserErrorType ], null: false

    def resolve(id:, **attrs)
      patient = current_organization.patients.find(id)
      authorize!(patient, :update?)

      if patient.update(attrs)
        { patient: patient, errors: [] }
      else
        { patient: nil, errors: user_errors_from(patient) }
      end
    end
  end
end

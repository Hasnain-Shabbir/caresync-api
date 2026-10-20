module Mutations
  class CreatePatient < BaseMutation
    null true

    argument :organization_id, ID, required: true
    argument :first_name, String, required: true
    argument :last_name, String, required: true
    argument :date_of_birth, GraphQL::Types::ISO8601Date, required: true

    # Return type: graphql-ruby generates CreatePatientPayload from these two fields.
    field :patient, Types::PatientType
    field :errors, [ Types::UserErrorType ], null: false

    def resolve(**attrs)
      patient = Patient.new(attrs)

      if patient.save
        { patient: patient, errors: [] }
      else
        { patient: nil, errors: user_errors_from(patient) }
      end
    end
  end
end

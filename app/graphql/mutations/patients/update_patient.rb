module Mutations
  module Patients
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

        result = ::Patients::Update.call(patient: patient, attributes: attrs)

        if result.success?
          { patient: result.value, errors: [] }
        else
          { patient: nil, errors: user_errors_from(result.value) }
        end
      end
    end
  end
end

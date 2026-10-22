module Patients
  class Create
    def self.call(...) = new(...).call

    def initialize(organization:, attributes:)
      @organization = organization
      @attributes = attributes
    end

    def call
      patient = @organization.patients.new(@attributes)

      if patient.save
        Result.success(patient)
      else
        Result.failure("VALIDATION_FAILED", "Patient is invalid", patient)
      end
    end
  end
end

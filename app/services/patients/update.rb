module Patients
  class Update
    def self.call(...) = new(...).call

    def initialize(patient:, attributes:)
      @patient = patient
      @attributes = attributes
    end

    def call
      if @patient.update(@attributes)
        Result.success(@patient)
      else
        Result.failure("VALIDATION_FAILED", "Patient is invalid", @patient)
      end
    end
  end
end

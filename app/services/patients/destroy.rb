module Patients
  class Destroy
    def self.call(...) = new(...).call

    def initialize(patient:)
      @patient = patient
    end

    def call
      @patient.destroy!
      Result.success(@patient)
    end
  end
end

require "test_helper"

class Patients::DestroyTest < ActiveSupport::TestCase
  test "deletes the patient" do
    patient = patients(:alice)

    result = Patients::Destroy.call(patient: patient)

    assert result.success?
    assert_not Patient.exists?(patient.id)
  end
end

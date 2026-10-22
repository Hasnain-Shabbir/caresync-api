require "test_helper"

class Patients::UpdateTest < ActiveSupport::TestCase
  test "updates the patient" do
    patient = patients(:alice)

    result = Patients::Update.call(patient: patient, attributes: { first_name: "Alicia" })

    assert result.success?
    assert_equal "Alicia", patient.reload.first_name
  end

  test "returns VALIDATION_FAILED and keeps the stored data when invalid" do
    patient = patients(:alice)

    result = Patients::Update.call(patient: patient, attributes: { first_name: nil })

    assert result.failure?
    assert_equal "VALIDATION_FAILED", result.code
    assert_equal "Alice", patient.reload.first_name
  end
end

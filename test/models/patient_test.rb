require "test_helper"

class PatientTest < ActiveSupport::TestCase
  test "is valid with all required attributes" do
    patient = Patient.new(organization: organizations(:sunrise),
                          first_name: "Cy", last_name: "Cole", date_of_birth: Date.new(2000, 1, 1))
    assert patient.valid?
  end

  test "requires a first and last name" do
    patient = patients(:alice)
    patient.first_name = nil
    assert_not patient.valid?
    patient.first_name = "Alice"
    patient.last_name = nil
    assert_not patient.valid?
  end

  test "requires a date of birth" do
    patient = patients(:alice)
    patient.date_of_birth = nil
    assert_not patient.valid?
  end

  test "belongs to an organization" do
    assert_equal organizations(:sunrise), patients(:alice).organization
  end
end

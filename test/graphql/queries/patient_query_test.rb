require "test_helper"

class PatientQueryTest < ActiveSupport::TestCase
  QUERY = "query($id: ID!) { patient(id: $id) { id firstName lastName dateOfBirth } }".freeze

  def execute(id)
    CaresyncApiSchema.execute(QUERY, variables: { id: id }, context: {}).to_h
  end

  test "patient returns one patient by id" do
    patient = patients(:alice)
    result = execute(patient.id.to_s)

    assert_nil result["errors"]
    assert_equal(
      { "id" => patient.id.to_s, "firstName" => "Alice", "lastName" => "Adams", "dateOfBirth" => "1990-04-12" },
      result.dig("data", "patient")
    )
  end

  test "patient with an unknown id returns null and a NOT_FOUND error" do
    result = execute("0")

    assert_not_nil result["data"]
    assert_nil result.dig("data", "patient")
    error = result["errors"].first
    assert_equal "Patient not found", error["message"]
    assert_equal "NOT_FOUND", error.dig("extensions", "code")
  end
end

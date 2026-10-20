require "test_helper"

class PatientMutationsTest < ActiveSupport::TestCase
  CREATE = <<~GQL
    mutation($input: CreatePatientInput!) {
      createPatient(input: $input) {
        patient { id firstName lastName dateOfBirth }
        errors { message path code }
      }
    }
  GQL

  def execute(query, input)
    CaresyncApiSchema.execute(query, variables: { input: input }, context: {}).to_h
  end

  def valid_create_input(overrides = {})
    {
      organizationId: organizations(:valley).id.to_s,
      firstName: "Ann",
      lastName: "Lee",
      dateOfBirth: "1992-06-15"
    }.merge(overrides)
  end

  # createPatient

  test "create succeeds with valid input" do
    result = nil
    assert_difference("Patient.count", 1) do
      result = execute(CREATE, valid_create_input)
    end

    payload = result.dig("data", "createPatient")
    assert_equal [], payload["errors"]
    assert_equal "Ann", payload.dig("patient", "firstName")
    assert_equal "Lee", payload.dig("patient", "lastName")
    assert_equal "1992-06-15", payload.dig("patient", "dateOfBirth")
  end

  test "create saves the patient under the given organization" do
    result = execute(CREATE, valid_create_input)

    patient = Patient.find(result.dig("data", "createPatient", "patient", "id"))
    assert_equal organizations(:valley), patient.organization
    assert_equal Date.new(1992, 6, 15), patient.date_of_birth
  end

  test "create returns a validation error for a blank first name" do
    result = nil
    assert_no_difference("Patient.count") do
      result = execute(CREATE, valid_create_input(firstName: ""))
    end

    payload = result.dig("data", "createPatient")
    assert_nil payload["patient"]
    error = payload["errors"].first
    assert_equal "VALIDATION_FAILED", error["code"]
    assert_equal [ "input", "firstName" ], error["path"]
    assert_match(/can't be blank/, error["message"])
  end

  test "create returns a validation error for a blank last name" do
    result = nil
    assert_no_difference("Patient.count") do
      result = execute(CREATE, valid_create_input(lastName: ""))
    end

    error = result.dig("data", "createPatient", "errors").first
    assert_equal "VALIDATION_FAILED", error["code"]
    assert_equal [ "input", "lastName" ], error["path"]
  end

  test "create returns every validation error when several fields are blank" do
    result = nil
    assert_no_difference("Patient.count") do
      result = execute(CREATE, valid_create_input(firstName: "", lastName: ""))
    end

    paths = result.dig("data", "createPatient", "errors").map { |e| e["path"] }
    assert_includes paths, [ "input", "firstName" ]
    assert_includes paths, [ "input", "lastName" ]
  end

  test "create returns a validation error for an organization that does not exist" do
    result = nil
    assert_no_difference("Patient.count") do
      result = execute(CREATE, valid_create_input(organizationId: "0"))
    end

    payload = result.dig("data", "createPatient")
    assert_nil payload["patient"]
    error = payload["errors"].first
    assert_equal "VALIDATION_FAILED", error["code"]
    assert_match(/must exist/, error["message"])
  end

  test "create rejects an invalid date before running the mutation" do
    result = nil
    assert_no_difference("Patient.count") do
      result = execute(CREATE, valid_create_input(dateOfBirth: "not-a-date"))
    end

    assert_nil result["data"]
    assert result["errors"].present?
  end

  test "create rejects a missing required argument" do
    input = valid_create_input.except(:firstName)
    result = nil
    assert_no_difference("Patient.count") do
      result = execute(CREATE, input)
    end

    assert_nil result["data"]
    assert_match(/firstName/, result["errors"].first["message"])
  end
end

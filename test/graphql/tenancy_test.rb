require "test_helper"

# Two tenants, both with a user and patients (see the fixtures):
#   Sunrise Clinic: admin_sunrise, nurse_sunrise, patients alice and bob
#   Valley Health:  admin_valley,                 patient carol
# A user from one organization must never reach the other's data.
class TenancyTest < ActiveSupport::TestCase
  def execute(query, variables: {}, as: users(:admin_sunrise))
    CaresyncApiSchema.execute(query, variables: variables, context: graphql_context(as)).to_h
  end

  def assert_not_found(result, field)
    assert_nil result.dig("data", field)
    assert_equal "NOT_FOUND", result["errors"]&.first&.dig("extensions", "code"), result.inspect
  end

  # The fixtures themselves

  test "fixtures: the second tenant has its own user and patient" do
    assert_equal organizations(:valley), users(:admin_valley).organization
    assert_equal organizations(:valley), patients(:carol).organization
    assert_equal [ patients(:carol) ], organizations(:valley).patients.to_a
    assert_equal [ users(:admin_valley) ], organizations(:valley).users.to_a
  end

  test "fixtures: the first tenant keeps its own users and patients" do
    assert_equal [ patients(:alice), patients(:bob) ].sort_by(&:id), organizations(:sunrise).patients.sort_by(&:id)
    assert_equal [ users(:admin_sunrise), users(:nurse_sunrise) ].sort_by(&:id), organizations(:sunrise).users.sort_by(&:id)
  end

  test "fixtures: the valley user can authenticate with the shared password" do
    assert users(:admin_valley).valid_password?("password")
  end

  # Organizations

  test "a user sees only their own organization in the list" do
    names = execute("{ organizations { name } }").dig("data", "organizations").map { |o| o["name"] }

    assert_equal [ "Sunrise Clinic" ], names
  end

  test "a user cannot fetch another organization by id" do
    result = execute("query($id: ID!) { organization(id: $id) { name } }", variables: { id: organizations(:valley).id.to_s })

    assert_not_found result, "organization"
  end

  test "a user can fetch their own organization by id" do
    result = execute("query($id: ID!) { organization(id: $id) { name } }", variables: { id: organizations(:sunrise).id.to_s })

    assert_equal "Sunrise Clinic", result.dig("data", "organization", "name")
  end

  test "a user cannot rename another organization, and its name is unchanged" do
    mutation = "mutation($input: UpdateOrganizationInput!) { updateOrganization(input: $input) { organization { name } } }"
    result = execute(mutation, variables: { input: { id: organizations(:valley).id.to_s, name: "Hijacked" } })

    assert_not_found result, "updateOrganization"
    assert_equal "Valley Health", organizations(:valley).reload.name
  end

  # Patients: reading

  test "a user can fetch their own patient" do
    result = execute("query($id: ID!) { patient(id: $id) { firstName } }", variables: { id: patients(:alice).id.to_s })

    assert_equal "Alice", result.dig("data", "patient", "firstName")
  end

  test "a user cannot fetch another organization's patient" do
    result = execute("query($id: ID!) { patient(id: $id) { firstName } }", variables: { id: patients(:carol).id.to_s })

    assert_not_found result, "patient"
  end

  test "the patient list contains only the user's own patients" do
    names = execute("{ patients { firstName } }").dig("data", "patients").map { |p| p["firstName"] }

    assert_equal %w[Alice Bob], names.sort
    assert_not_includes names, "Carol"
  end

  test "a missing record and another tenant's record give the same error" do
    other_tenant = execute("query($id: ID!) { patient(id: $id) { id } }", variables: { id: patients(:carol).id.to_s })
    missing = execute("query($id: ID!) { patient(id: $id) { id } }", variables: { id: "0" })

    assert_equal missing["errors"].first["message"], other_tenant["errors"].first["message"]
    assert_equal missing["errors"].first.dig("extensions", "code"), other_tenant["errors"].first.dig("extensions", "code")
  end

  test "nested patients under an organization only list that organization's patients" do
    result = execute("{ organizations { name patients { firstName } } }")

    patients = result.dig("data", "organizations").flat_map { |o| o["patients"] }.map { |p| p["firstName"] }
    assert_equal %w[Alice Bob], patients.sort
  end

  # Patients: writing

  test "a user cannot update another organization's patient, and it is unchanged" do
    mutation = "mutation($input: UpdatePatientInput!) { updatePatient(input: $input) { patient { id } } }"
    result = execute(mutation, variables: { input: { id: patients(:carol).id.to_s, firstName: "Hijacked" } })

    assert_not_found result, "updatePatient"
    assert_equal "Carol", patients(:carol).reload.first_name
  end

  test "a user cannot delete another organization's patient, and it still exists" do
    mutation = "mutation($input: DeletePatientInput!) { deletePatient(input: $input) { deletedId } }"
    result = nil

    assert_no_difference("Patient.count") do
      result = execute(mutation, variables: { input: { id: patients(:carol).id.to_s } })
    end

    assert_not_found result, "deletePatient"
    assert Patient.exists?(patients(:carol).id)
  end

  test "a created patient always belongs to the user's own organization" do
    mutation = "mutation($input: CreatePatientInput!) { createPatient(input: $input) { patient { id } errors { message } } }"
    input = { firstName: "New", lastName: "Patient", dateOfBirth: "2000-01-01" }

    result = execute(mutation, variables: { input: input }, as: users(:admin_valley))

    patient = Patient.find(result.dig("data", "createPatient", "patient", "id"))
    assert_equal organizations(:valley), patient.organization
  end

  test "a client cannot choose the organization when creating a patient" do
    mutation = "mutation($input: CreatePatientInput!) { createPatient(input: $input) { patient { id } } }"
    input = { organizationId: organizations(:valley).id.to_s, firstName: "New", lastName: "Patient", dateOfBirth: "2000-01-01" }
    result = nil

    assert_no_difference("Patient.count") do
      result = execute(mutation, variables: { input: input })
    end

    assert_nil result["data"]
    assert result["errors"].present?
  end

  # The other tenant, seen from its own side

  test "the valley user sees only valley data" do
    org_names = execute("{ organizations { name } }", as: users(:admin_valley)).dig("data", "organizations").map { |o| o["name"] }
    patient_names = execute("{ patients { firstName } }", as: users(:admin_valley)).dig("data", "patients").map { |p| p["firstName"] }

    assert_equal [ "Valley Health" ], org_names
    assert_equal [ "Carol" ], patient_names
  end

  test "the valley user cannot fetch a sunrise patient" do
    result = execute("query($id: ID!) { patient(id: $id) { firstName } }",
                     variables: { id: patients(:alice).id.to_s }, as: users(:admin_valley))

    assert_not_found result, "patient"
  end
end

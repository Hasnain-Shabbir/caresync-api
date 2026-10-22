require "test_helper"

class Patients::CreateTest < ActiveSupport::TestCase
  test "creates a patient inside the given organization" do
    organization = organizations(:sunrise)

    result = Patients::Create.call(
      organization: organization,
      attributes: { first_name: "Cy", last_name: "Cole", date_of_birth: Date.new(2000, 1, 1) }
    )

    assert result.success?
    assert_equal organization, result.value.organization
    assert result.value.persisted?
  end

  test "returns VALIDATION_FAILED with the invalid record when data is missing" do
    result = Patients::Create.call(organization: organizations(:sunrise), attributes: { first_name: "Cy" })

    assert result.failure?
    assert_equal "VALIDATION_FAILED", result.code
    assert_not result.value.persisted?
    assert result.value.errors[:last_name].any?
  end
end

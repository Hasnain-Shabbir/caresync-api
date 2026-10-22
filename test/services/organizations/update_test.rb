require "test_helper"

class Organizations::UpdateTest < ActiveSupport::TestCase
  test "updates the organization" do
    organization = organizations(:sunrise)

    result = Organizations::Update.call(organization: organization, attributes: { name: "Sunrise Health" })

    assert result.success?
    assert_equal "Sunrise Health", organization.reload.name
  end

  test "returns VALIDATION_FAILED and keeps the stored name when invalid" do
    organization = organizations(:sunrise)

    result = Organizations::Update.call(organization: organization, attributes: { name: "" })

    assert result.failure?
    assert_equal "VALIDATION_FAILED", result.code
    assert_equal "Sunrise Clinic", organization.reload.name
  end
end

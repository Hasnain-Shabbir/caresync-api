require "test_helper"

class OrganizationTest < ActiveSupport::TestCase
  test "is valid with a name" do
    org = Organization.new(name: "Acme Care")
    assert org.valid?
  end

  test "is invalid without a name" do
    org = Organization.new(name: nil)
    assert_not org.valid?
    assert_includes org.errors[:name], "can't be blank"
  end

  test "is invalid with a duplicate name" do
    org = Organization.new(name: organizations(:sunrise).name)
    assert_not org.valid?
    assert_includes org.errors[:name], "has already been taken"
  end
end

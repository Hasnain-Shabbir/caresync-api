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

  test "has many users and patients" do
    assert_equal 2, organizations(:sunrise).users.count
    assert_equal 2, organizations(:sunrise).patients.count
  end

  test "cannot be destroyed while it has patients" do
    assert_raises(ActiveRecord::DeleteRestrictionError) do
      organizations(:sunrise).destroy!
    end
  end

  test "can be destroyed when it has no users or patients" do
    empty = Organization.create!(name: "Empty Clinic")

    assert_difference("Organization.count", -1) do
      empty.destroy!
    end
  end
end

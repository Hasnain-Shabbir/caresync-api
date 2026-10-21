require "test_helper"

class UserTest < ActiveSupport::TestCase
  def build_user(**overrides)
    User.new({
      organization: organizations(:sunrise),
      email: "new@sunrise.test",
      password: "a-long-password-1",
      first_name: "New",
      last_name: "User"
    }.merge(overrides))
  end

  test "is valid with all required attributes" do
    assert build_user.valid?
  end

  test "requires an email" do
    assert_not build_user(email: nil).valid?
  end

  test "rejects a badly formatted email" do
    assert_not build_user(email: "not-an-email").valid?
  end

  test "normalizes email to lowercase and trims it" do
    assert_equal "mixed@sunrise.test", build_user(email: "  Mixed@Sunrise.TEST ").email
  end

  test "email must be unique" do
    assert_not build_user(email: users(:admin_sunrise).email).valid?
  end

  test "email uniqueness ignores case" do
    assert_not build_user(email: "ADMIN@sunrise.test").valid?
  end

  test "requires first and last name" do
    assert_not build_user(first_name: nil).valid?
    assert_not build_user(last_name: nil).valid?
  end

  test "rejects an unknown role" do
    assert_not build_user(role: "superuser").valid?
  end

  test "defaults to the front_desk role" do
    assert build_user.front_desk?
  end

  test "belongs to an organization" do
    assert_equal organizations(:sunrise), users(:admin_sunrise).organization
  end
end

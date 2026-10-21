require "test_helper"

class OrganizationPolicyTest < ActiveSupport::TestCase
  ROLE_FIXTURES = {
    admin: :admin_sunrise,
    provider: :provider_sunrise,
    nurse: :nurse_sunrise,
    front_desk: :front_desk_sunrise
  }.freeze

  def policy_for(role)
    OrganizationPolicy.new(users(ROLE_FIXTURES.fetch(role)), organizations(:sunrise))
  end

  test "every role may view the organization" do
    ROLE_FIXTURES.each_key do |role|
      assert policy_for(role).show?, "#{role} should be able to view the organization"
    end
  end

  test "only an admin may update the organization" do
    assert policy_for(:admin).update?

    %i[provider nurse front_desk].each do |role|
      assert_not policy_for(role).update?, "#{role} should not be able to update the organization"
    end
  end

  test "nobody may create or destroy an organization through the policy" do
    ROLE_FIXTURES.each_key do |role|
      assert_not policy_for(role).create?, "#{role} should not create organizations"
      assert_not policy_for(role).destroy?, "#{role} should not destroy organizations"
    end
  end

  test "listing organizations is denied by default" do
    ROLE_FIXTURES.each_key do |role|
      assert_not policy_for(role).index?
    end
  end
end

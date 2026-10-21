require "test_helper"

# Default-deny: a policy that grants nothing must refuse everything.
class ApplicationPolicyTest < ActiveSupport::TestCase
  test "a bare policy denies every action, even for an admin" do
    policy = ApplicationPolicy.new(users(:admin_sunrise), patients(:alice))

    %i[index? show? create? new? update? edit? destroy?].each do |action|
      assert_equal false, policy.public_send(action), "#{action} should be denied by default"
    end
  end

  test "a policy class that grants nothing denies everything" do
    nothing_granted = Class.new(ApplicationPolicy)
    policy = nothing_granted.new(users(:admin_sunrise), organizations(:sunrise))

    assert_equal false, policy.update?
    assert_equal false, policy.destroy?
  end

  test "a policy is found for the models we authorize" do
    assert_instance_of PatientPolicy, Pundit.policy!(users(:admin_sunrise), patients(:alice))
    assert_instance_of OrganizationPolicy, Pundit.policy!(users(:admin_sunrise), organizations(:sunrise))
  end

  test "asking for a policy that does not exist raises instead of allowing" do
    assert_raises(Pundit::NotDefinedError) { Pundit.policy!(users(:admin_sunrise), Object.new) }
  end
end

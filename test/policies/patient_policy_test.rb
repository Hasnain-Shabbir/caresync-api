require "test_helper"

# One test per cell of the permission matrix in guide 07, so a policy change has to be deliberate.
class PatientPolicyTest < ActiveSupport::TestCase
  ROLE_FIXTURES = {
    admin: :admin_sunrise,
    provider: :provider_sunrise,
    nurse: :nurse_sunrise,
    front_desk: :front_desk_sunrise
  }.freeze

  # action => roles that are allowed (everyone else must be refused)
  MATRIX = {
    index?: %i[admin provider nurse front_desk],
    show?: %i[admin provider nurse front_desk],
    create?: %i[admin provider front_desk],
    update?: %i[admin provider nurse],
    destroy?: %i[admin],
    view_date_of_birth?: %i[admin provider nurse]
  }.freeze

  def policy_for(role)
    PatientPolicy.new(users(ROLE_FIXTURES.fetch(role)), patients(:alice))
  end

  MATRIX.each do |action, allowed_roles|
    ROLE_FIXTURES.each_key do |role|
      expected = allowed_roles.include?(role)

      test "#{role} #{expected ? 'may' : 'may not'} #{action.to_s.chomp('?')} a patient" do
        assert_equal expected, policy_for(role).public_send(action)
      end
    end
  end

  test "the fixtures really have the roles the matrix assumes" do
    ROLE_FIXTURES.each do |role, fixture|
      assert_equal role.to_s, users(fixture).role
    end
  end

  test "every action in the policy appears in the matrix" do
    public_actions = PatientPolicy.public_instance_methods(false).select { |m| m.to_s.end_with?("?") }

    assert_equal [], public_actions - MATRIX.keys, "these policy methods have no test in the matrix"
  end

  test "new? follows create? and edit? follows update? for every role" do
    ROLE_FIXTURES.each_key do |role|
      policy = policy_for(role)

      assert_equal policy.create?, policy.new?
      assert_equal policy.update?, policy.edit?
    end
  end
end

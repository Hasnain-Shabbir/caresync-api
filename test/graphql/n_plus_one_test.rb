require "test_helper"

class NPlusOneTest < ActiveSupport::TestCase
  QUERY = "{ patients(perPage: 30) { patients { firstName organization { name } } } }".freeze

  # NOTE: loading patients through current_organization.patients already sets each patient's organization from the
  # loaded one (the inverse association), so there is nothing to batch on this path today. This test cannot fail
  # yet. It guards the page query against someone later changing the scope or adding a field that loads per row.
  def count_queries
    count = 0
    counter = ->(*, payload) { count += 1 unless payload[:name] == "SCHEMA" || payload[:cached] }
    ActiveSupport::Notifications.subscribed(counter, "sql.active_record") { yield }
    count
  end

  def queries_for_one_page
    context = graphql_context
    context[:current_user].organization # load the user and organization before counting, so those SELECTs aren't counted
    count_queries { CaresyncApiSchema.execute(QUERY, context: context) }
  end

  test "a page of patients with their organization uses the same number of queries for 2 patients or 12" do
    few = queries_for_one_page

    10.times do |i|
      Patient.create!(organization: organizations(:sunrise), first_name: "P#{i}", last_name: "L#{i}", date_of_birth: "1990-01-01")
    end

    assert_equal few, queries_for_one_page
  end
end

require "test_helper"

class NPlusOneTest < ActiveSupport::TestCase
  def count_queries
    count = 0
    counter = ->(*, payload) { count += 1 unless payload[:name] == "SCHEMA" || payload[:cached] }
    ActiveSupport::Notifications.subscribed(counter, "sql.active_record") { yield }
    count
  end

  setup do
    3.times do |i|
      org = Organization.create!(name: "Extra Org #{i}")
      Patient.create!(organization: org, first_name: "P#{i}", last_name: "L#{i}", date_of_birth: "1990-01-01")
    end
  end

  test "listing organizations with their patients uses a constant number of queries" do
    context = graphql_context # load the user fixture before counting, so its SELECT isn't counted

    queries = count_queries do
      CaresyncApiSchema.execute("{ organizations { name patients { firstName } } }", context: context)
    end

    # 1 query for the organizations + 1 batched query for all their patients,
    # however many organizations there are.
    assert_equal 2, queries
  end
end

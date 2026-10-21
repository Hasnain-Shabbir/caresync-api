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
      Patient.create!(organization: organizations(:sunrise), first_name: "P#{i}", last_name: "L#{i}", date_of_birth: "1990-01-01")
    end
  end

  # NOTE: a logged-in user now sees only their own organization, so this query can no longer
  # fan out across several organizations. It still checks that loading patients stays at one
  # batched query, but it cannot expose an N+1 across organizations by itself. Add a case here
  # when the schema has a real list of parents with children (for example an admin-wide view).
  test "listing organizations with their patients uses a constant number of queries" do
    context = graphql_context
    context[:current_user].organization # load the user and organization before counting, so those SELECTs aren't counted

    queries = count_queries do
      CaresyncApiSchema.execute("{ organizations { name patients { firstName } } }", context: context)
    end

    # 1 query for the organizations + 1 batched query for their patients.
    assert_equal 2, queries
  end
end

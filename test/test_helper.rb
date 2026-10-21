ENV["RAILS_ENV"] ||= "test"
require_relative "../config/environment"
require "rails/test_help"
require "devise/jwt/test_helpers"

module ActiveSupport
  class TestCase
    # Run tests in parallel with specified workers
    parallelize(workers: :number_of_processors)

    # Setup all fixtures in test/fixtures/*.yml for all tests in alphabetical order.
    fixtures :all

    # Add more helper methods to be used by all tests here...
    def graphql_context(user = users(:admin_sunrise))
      { current_user: user }
    end

    # Headers with a valid Bearer token for a user (for request tests).
    def auth_headers(user = users(:admin_sunrise))
      Devise::JWT::TestHelpers.auth_headers({}, user)
    end
  end
end

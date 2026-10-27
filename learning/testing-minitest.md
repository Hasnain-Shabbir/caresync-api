# Testing with Minitest (what Rails ships with)

Source: [Rails Guides: Testing Rails Applications](https://guides.rubyonrails.org/testing.html)
Express comparison: Minitest is like Jest, `test "..." do ... end` is `it(...)`. Request tests are like supertest. We may switch to RSpec later (see ROADMAP Phase 1).

## Assertions you'll use
```ruby
assert user.valid?                       # truthy
assert_not user.valid?                   # falsy
assert_equal "Hi", article.title         # EXPECTED first, ACTUAL second (opposite of some JS habits)
assert_raises(ActiveRecord::RecordInvalid) { Organization.create!(name: nil) }
assert_difference("Organization.count", 1) { Organization.create!(name: "Acme") }
```

## Fixtures
- YAML files in `test/fixtures/`, one per table. Each top-level key is a label for a row.
- Rails wipes the table and inserts these rows before the tests run. Each test then runs in a transaction that is rolled back.
- Access them with `organizations(:sunrise)`.

```yaml
sunrise:
  name: Sunrise Clinic
```
- Gotcha (from experience, not stated on this page): fixtures are inserted directly with SQL, so model validations don't run, but DB constraints (`null: false`, unique indexes) do. A bad fixture makes the whole suite crash at load time.
- Fixture values must satisfy the DB constraints, even though validations are skipped.

## Running tests
```bash
bin/rails test                                   # all
bin/rails test test/models/organization_test.rb  # one file
bin/rails test test/models/organization_test.rb:12   # test at that line
bin/rails test -n test_name                      # by name
```

## Request tests for a JSON API
Go in `test/integration/` (or `test/controllers/`), inherit from `ActionDispatch::IntegrationTest`.

```ruby
class OrganizationsApiTest < ActionDispatch::IntegrationTest
  test "lists organizations" do
    get api_v1_organizations_url, as: :json
    assert_response :success
  end

  test "creates" do
    post api_v1_organizations_url, params: { organization: { name: "Acme" } }, as: :json
    assert_response :created
  end
end
```
- `get/post/patch/put/delete` take `params:`, `headers:`, `as: :json`.
- `assert_response` accepts `:success` (2xx), `:redirect`, `:missing` (404), `:error` (5xx), or a symbol like `:created` / `:unprocessable_entity`.
- Read the response with `response.body` (a string). To parse JSON use `JSON.parse(response.body)`, or `response.parsed_body` (also exists in Rails, not covered on the guide page).

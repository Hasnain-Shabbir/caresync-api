# Strong parameters and building a `create` action

Sources: [Action Controller Overview, Strong Parameters](https://guides.rubyonrails.org/action_controller_overview.html), [Active Record Validations](https://guides.rubyonrails.org/active_record_validations.html) (see also [active-record-validations.md](active-record-validations.md)), error handling in [rescue-from-error-handling.md](rescue-from-error-handling.md).

---

## 1. The problem

A client sends this when it creates an organization:
```json
POST /api/v1/organizations
{ "organization": { "name": "Sunrise Clinic" } }
```
Rails puts it in `params`. The risk is **mass assignment**: if you did `Organization.create(params[:organization])` and the client also sent `{"name": "X", "admin": true, "id": 1}`, every key would go straight into the model. Today `Organization` has only `name`, but later models will have `role`, `organization_id`, `is_admin`, and so on.

**Strong parameters** make you list explicitly which keys are allowed. Everything else is dropped.

Express comparison: it's the same job as `Joi`/`Zod` schemas with `stripUnknown`, or manually picking `const { name } = req.body`.

---

## 2. What Rails does for you

Rails refuses unpermitted data by design:
- `Organization.create(params[:organization])` (raw params) raises `ActiveModel::ForbiddenAttributesError`.
- Keys you don't permit are **filtered out** (dropped).
- Permitted values must be simple values (strings, numbers, booleans, dates). Arrays and hashes must be declared explicitly.

---

## 3. `params.expect` (use this one)

```ruby
params.expect(organization: [:name])
```
Read it as: "I **expect** a top-level key `organization` that is a hash, and from it I allow only `name`."

What it does:
- If the `organization` key is **missing** or isn't a hash with the right shape, it raises `ActionController::ParameterMissing`, which Rails treats as **400 Bad Request**.
- If present, it returns a permitted params object containing only `name`. Extra keys are dropped.

Allowing several keys: `params.expect(patient: [:first_name, :last_name, :date_of_birth])`.

### `expect` vs `permit` vs `require`
| Method | Checks the root key exists? | Notes |
|---|---|---|
| `params.expect(organization: [:name])` | **Yes**, raises ParameterMissing (400) | Recommended in Rails 8. One call. |
| `params.require(:organization).permit(:name)` | Yes | The older two-step way. You'll see it in most existing code, so know how to read it. |
| `params.permit(:name)` | No | Only filters. Doesn't check the root key. |
| `permit!` | no | Allows everything. **Never use it.** |

---

## 4. The private params method

Put the allowed list in one private method so `create` and `update` share it:

```ruby
private

def organization_params
  params.expect(organization: [:name])
end
```
Then use `Organization.new(organization_params)`. The method name is a convention (`<model>_params`), not a Rails rule.

---

## 5. `save` vs `save!`, `create` vs `create!`

| Version | On validation failure |
|---|---|
| `save` / `create` | returns `false` / an unsaved object. **No exception.** |
| `save!` / `create!` | raises `ActiveRecord::RecordInvalid`. |

Two ways to write the action:

**Style 1: `create!` and a `rescue_from` (the style we use).**
```ruby
def create
  organization = Organization.create!(organization_params)
  render json: organization, status: :created
end
```
- The action only has the happy path.
- On failure, `RecordInvalid` is raised, and the `rescue_from` in `ApplicationController` renders the 422 envelope. The action doesn't know about errors.

**Style 2: `save` and an `if`.**
```ruby
organization = Organization.new(organization_params)
if organization.save
  render json: organization, status: :created
else
  render json: { errors: organization.errors }, status: :unprocessable_content
end
```
This repeats in every controller, which is why we use style 1.

---

## 6. The response for a successful `create`
- Status **201 Created** (`:created`), not 200.
- Body: the created record.
- (Many APIs also send a `Location` header pointing at the new resource. Optional here.)

---

## 7. Failures and what the client should see

| Client sends | Rails raises | Status |
|---|---|---|
| `{}` (no `organization` key) | `ActionController::ParameterMissing` | 400 |
| `{"organization": {}}` | `ParameterMissing` (empty hash fails `expect`) | 400 |
| `{"organization": {"name": ""}}` | `ActiveRecord::RecordInvalid` (name can't be blank) | 422 |
| duplicate name (uniqueness) | `ActiveRecord::RecordInvalid` | 422 |

Both are handled by `rescue_from` in `ApplicationController`, using the same envelope as `not_found`. `RecordInvalid` has `exception.record.errors` to fill `details`, and `ParameterMissing` has `exception.param`.

---

## 8. Testing a create in minitest
Request tests post JSON with `as: :json`:
```ruby
post api_v1_organizations_url, params: { organization: { name: "New Clinic" } }, as: :json
```
- Check the status with `assert_response :created`.
- Check the record count changed with `assert_difference("Organization.count", 1) do ... end`.
- Check that nothing was created on failure with `assert_no_difference("Organization.count") do ... end`.
- Read the body with `response.parsed_body`.

---

## 9. HIPAA note (for later)
Strong params are also a safety control: they stop a user from setting fields like `role` or `organization_id` that they shouldn't control. Later, `organization_id` will come from the logged-in user (`Current.organization`), **never** from the request body.

---

## 10. Self-check questions
1. What attack does strong parameters prevent? Give an example for a `User` model with a `role` column.
2. What is the difference between `params.expect(organization: [:name])` and `params.permit(:name)` when the request has no `organization` key?
3. What status does Rails return for `ParameterMissing` by default, and what do we change about it?
4. Why do we use `create!` plus `rescue_from` instead of `if organization.save`?
5. What happens to `{"organization": {"name": "X", "id": 5}}`? Is `id` saved?

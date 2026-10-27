# Guide 03: Mutations and errors-as-data

Roadmap step 3 of [GRAPHQL-ROADMAP.md](../GRAPHQL-ROADMAP.md). You implement it. This guide explains **why** first, then **what to type**.
Sources: [Mutation classes](https://graphql-ruby.org/mutations/mutation_classes), [Mutation errors](https://graphql-ruby.org/mutations/mutation_errors).

Goal: `createOrganization`, `updateOrganization`, `deleteOrganization` over `POST /graphql`, with the same behaviour as the REST CRUD (validation errors, not found, can't delete an organization that still has patients), plus tests.

---

## 1. Concepts

### Query vs mutation
Queries read. Mutations write. The difference is a convention, but graphql-ruby enforces one rule: top-level mutation fields run **one after another**, queries may run in parallel. So put every write behind a mutation.

### One class per mutation
In REST each write was an action in a controller (`create`, `update`, `destroy`). In graphql-ruby each write is a **class** in `app/graphql/mutations/` with:
- `argument`: the inputs
- `field`: what the payload contains
- `resolve`: the code that does the work

You register it on `Types::MutationType` with `field :create_organization, mutation: Mutations::CreateOrganization`.

### What `RelayClassicMutation` gives you
The generated `Mutations::BaseMutation` inherits from `GraphQL::Schema::RelayClassicMutation`. It auto-generates two types from your class:

| You write | graphql-ruby generates |
|---|---|
| `Mutations::CreateOrganization` | input type `CreateOrganizationInput`, payload type `CreateOrganizationPayload` |
| `argument :name, String` | all arguments are wrapped in a single `input` argument |

So a client calls it like this:

```graphql
mutation($input: CreateOrganizationInput!) {
  createOrganization(input: $input) {
    organization { id name }
    errors { message path code }
  }
}
```
with variables `{ "input": { "name": "Acme" } }`. (It also adds an optional `clientMutationId`. Ignore it.)

### Errors: two kinds, and why
In REST you used HTTP status codes (404, 422, 409). GraphQL always answers HTTP 200, so errors travel in the body. There are two places:

| | Top-level `errors` | Errors **as data** (`errors` inside the payload) |
|---|---|---|
| How | `raise GraphQL::ExecutionError` (or `rescue_from`) | return a list of typed error objects |
| Good for | unexpected or "request is broken" cases: not found, not authenticated, bad id | **expected business failures**: validation failed, name taken, can't delete |
| Client | has to parse a message | gets typed fields (`message`, `path`, `code`) and can show them next to form fields |
| Type system | no | yes |

**Rule we follow in CareSync:**
- Validation failures and "conflicts" (in-use records) become **user errors in the payload**.
- Not found, auth and unexpected failures stay **top-level** errors with an `extensions.code`.

### Nullable payload fields (important gotcha)
If a payload field is `null: false` and you return nothing for it (because validation failed), GraphQL drops the **entire** mutation response, including your errors. So payload fields like `organization` must be **nullable** (which is the default for `field` on a mutation). Also set `null true` on the mutation so the whole payload may be null when a top-level error is raised.

---

## 2. Step by step

### 2.1 The error type

`app/graphql/types/user_error_type.rb`
```ruby
module Types
  class UserErrorType < Types::BaseObject
    field :message, String, null: false
    field :path, [ String ], null: true
    field :code, String, null: false
  end
end
```
Why: a typed error. `path` points at the input field (`["input", "name"]`) so a UI can mark the right box. `code` is a stable machine-readable value (`VALIDATION_FAILED`, `CONFLICT`). The docs' example has only `message` and `path`. The `code` field is our own addition. The class name `UserErrorType` appears as `UserError` in the schema (graphql-ruby strips the `Type` suffix).

### 2.2 Shared helper in the base mutation

In `app/graphql/mutations/base_mutation.rb`, add a method (leave the existing lines as they are):

```ruby
private

def user_errors_from(record)
  record.errors.map do |error|
    {
      message: error.full_message,
      path: [ "input", error.attribute.to_s.camelize(:lower) ],
      code: "VALIDATION_FAILED"
    }
  end
end
```
Why: all three mutations need to turn `record.errors` into the error shape. One helper avoids three copies. `camelize(:lower)` makes `date_of_birth` into `dateOfBirth`, matching what the client sent. `full_message` gives `"Name can't be blank"`.

### 2.3 The three mutations

`app/graphql/mutations/create_organization.rb`
```ruby
module Mutations
  class CreateOrganization < BaseMutation
    null true

    argument :name, String, required: true

    field :organization, Types::OrganizationType
    field :errors, [ Types::UserErrorType ], null: false

    def resolve(name:)
      organization = Organization.new(name: name)

      if organization.save
        { organization: organization, errors: [] }
      else
        { organization: nil, errors: user_errors_from(organization) }
      end
    end
  end
end
```

`update_organization.rb`: same shape, with `argument :id, ID, required: true` and `argument :name, String, required: true`. In `resolve(id:, name:)`: `organization = Organization.find(id)` and then `organization.update(name: name)`. Return the same payload shape.

`delete_organization.rb`: `argument :id, ID, required: true`. Payload: `field :deleted_id, ID` and `field :errors, ...`.
```ruby
def resolve(id:)
  organization = Organization.find(id)
  organization.destroy!
  { deleted_id: id, errors: [] }
rescue ActiveRecord::DeleteRestrictionError
  {
    deleted_id: nil,
    errors: [ { message: "Cannot delete an organization that still has users or patients",
                path: [ "input", "id" ], code: "CONFLICT" } ]
  }
end
```

Why each choice:
- `save` / `update` (no bang) return `false` instead of raising, so we can turn the errors into data. The REST controller used `create!` and `rescue_from` for this. Same idea, different style.
- `Organization.find` raises `RecordNotFound` on purpose. The schema's `rescue_from` (from guide 02) turns it into a top-level `NOT_FOUND` error. That matches the rule above.
- The delete restriction is an **expected** conflict, so it becomes a user error with `CONFLICT`. REST returned 409 for the same case.
- `resolve` receives the arguments as keyword arguments (`name:`), and must return a hash whose keys are the payload field names.

### 2.4 Fix the not-found message in the schema

In `caresync_api_schema.rb`, the `rescue_from` builds its message from `field.type.unwrap.graphql_name`. For a mutation, that's the **payload** type, so the message would read `UpdateOrganizationPayload not found`. Use the exception's model name instead (same idea as the REST handler):

```ruby
rescue_from(ActiveRecord::RecordNotFound) do |err, _obj, _args, _ctx, _field|
  raise GraphQL::ExecutionError.new(
    "#{err.model || 'Record'} not found",
    extensions: { code: "NOT_FOUND" }
  )
end
```
Why: `Organization.find(id)` sets `err.model` to `"Organization"`, so the message is right for both queries and mutations. This is a good example of a bug that only the **tests** would catch.

### 2.5 Register on the mutation root

`app/graphql/types/mutation_type.rb`: delete the generated `test_field` and its method, then add:
```ruby
field :create_organization, mutation: Mutations::CreateOrganization
field :update_organization, mutation: Mutations::UpdateOrganization
field :delete_organization, mutation: Mutations::DeleteOrganization
```
Why: this is what makes them callable. The GraphQL names are camelized (`createOrganization`).

---

## 3. Tests: `test/graphql/mutations/organization_mutations_test.rb`

Use the same `execute` helper as the queries test. Write these:

| # | Test | Expect |
|---|---|---|
| 1 | create with a valid name | `errors` is `[]`, `organization.name` set, `Organization.count` +1 (`assert_difference`) |
| 2 | create with a blank name | `organization` is null, one error with `code` `VALIDATION_FAILED` and `path` `["input", "name"]`, count unchanged |
| 3 | create with a duplicate name (`Sunrise Clinic`) | error message mentions `already been taken` |
| 4 | update with a valid name | name changed in the DB (`org.reload.name`) |
| 5 | update with a blank name | validation user error, name unchanged |
| 6 | update with an unknown id | `data.updateOrganization` is nil, top-level error `Organization not found` with `extensions.code` `NOT_FOUND` |
| 7 | delete `valley` (no users or patients) | `deletedId` returned, count -1 |
| 8 | delete `sunrise` (has users and patients) | `deletedId` null, error with `code` `CONFLICT`, count unchanged |

The mutation query to send:
```ruby
CREATE = <<~GQL
  mutation($input: CreateOrganizationInput!) {
    createOrganization(input: $input) {
      organization { id name }
      errors { message path code }
    }
  }
GQL
execute(CREATE, variables: { input: { name: "Acme" } })
```
Results come back camelized: `result.dig("data", "createOrganization", "errors")`.

Why test 6 matters: it proves 2.4 works for mutations and that `null true` lets the payload be null.

---

## 4. Verify

```bash
bin/rails test && bin/rubocop && bin/brakeman -q
curl -s localhost:4000/graphql -H 'Content-Type: application/json' -d '{
  "query": "mutation($input: CreateOrganizationInput!) { createOrganization(input: $input) { organization { id name } errors { message path code } } }",
  "variables": { "input": { "name": "Curl Clinic" } }
}'
```
Commit: `feat: add organization mutations with user errors`.

---

## 5. Self-check (answers below)

1. Why does a validation failure return HTTP 200 and not 422?
2. Why are payload fields like `organization` nullable?
3. Why is "not found" a top-level error but "name is blank" a user error?
4. What does `RelayClassicMutation` change about how a client sends arguments?
5. Why `save` and not `save!` in the create mutation?
6. In 2.4, why use `err.model` and not `field.type.unwrap.graphql_name`?
7. Why does `path` use camelCase (`dateOfBirth`)?

**Answers**
1. GraphQL separates transport from field results. The request was processed correctly, and the failure is reported in the body. Status codes would only describe the HTTP layer.
2. If the field were non-null and returned nothing, GraphQL would drop the whole response, including the errors we wanted the client to see.
3. Blank names are expected input mistakes the user can fix. They deserve typed, per-field errors. Not found means the client referenced something that doesn't exist, which is a broken request.
4. All arguments go inside one `input` object of type `<Name>Input`, and the payload is `<Name>Payload`.
5. `save` returns `false` so we can build the error list. `save!` would raise `RecordInvalid`, and we'd have to rescue it.
6. For a mutation the field's type is the payload (`UpdateOrganizationPayload`), not the record. `err.model` names the model that wasn't found.
7. It's what the client sent, so the UI can match errors to its input names.

---

## 6. What comes next

Guide 04: **relations and the N+1 problem**. `organizations { patients { ... } }` runs one query per organization right now. We measure it, then fix it with the dataloader.

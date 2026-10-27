# How to add a CRUD resource to the GraphQL API

A reusable checklist for anyone adding a new feature (a new model with queries and mutations) to CareSync.
Example used throughout: a hypothetical `Appointment` (belongs to a `Patient`, has `starts_at` and `reason`). Replace the names with your resource.

Conventions here come from what the project already does: [guide 02](guide-02-graphql-foundation.md) (foundation), [guide 03](guide-03-graphql-mutations.md) (mutations and errors), [guide 04](guide-04-patients-and-n-plus-one.md) (patients, N+1, dataloader). Read those once for the "why". This page is the "what to do, in order".

---

## 0. The order of work

1. Model, migration, fixtures, model tests (the database comes first)
2. GraphQL **type**
3. **Queries** (list and one)
4. **Mutations** (create, update, delete)
5. **Register** queries and mutations
6. **Relationships** and the N+1 fix
7. **Errors** (decide which kind where)
8. **Tests** for queries, mutations and query counts
9. **Verify** and commit

Do them in this order. Each step ends with something you can run, so a bug is found while it's still small.

## 1. File map: what you create

| What | Where | Name pattern |
|---|---|---|
| Model | `app/models/appointment.rb` | singular, `Appointment` |
| Migration | `db/migrate/..._create_appointments.rb` | `bin/rails generate model ...` |
| Fixtures | `test/fixtures/appointments.yml` | plural, labels like `checkup` |
| Type | `app/graphql/types/appointment_type.rb` | `Types::AppointmentType` |
| Queries | edit `app/graphql/types/query_type.rb` | field `appointment`, method `appointment` |
| Mutations | `app/graphql/mutations/create_appointment.rb`, `update_...`, `delete_...` | `Mutations::CreateAppointment` ... |
| Registration | edit `app/graphql/types/mutation_type.rb` | `field :create_appointment, mutation: ...` |
| Tests | `test/graphql/queries/appointment_query_test.rb`, `test/graphql/mutations/appointment_mutations_test.rb`, optional `test/graphql/n_plus_one_test.rb` | `<thing>_..._test.rb` |

**Golden rule:** the file name, the class name and the module must match. `update_appointment.rb` must define `Mutations::UpdateAppointment`. If not, Rails can't load it, and the **whole schema** fails (Postman and the sandbox show nothing).

## 2. Step 1: model first

```bash
bin/rails generate model Appointment patient:references starts_at:datetime reason:string
```
Then, before migrating, edit the migration:
- `null: false` on required columns
- a foreign key (`references` adds it, check it says `foreign_key: true`)
- an index for how you'll query (for example `[:patient_id, :starts_at]`)

In the model: `belongs_to :patient`, validations (`presence`, `uniqueness` with `scope:` where needed), and `dependent:` on the **parent's** `has_many` (we use `:restrict_with_exception` for PHI).

```bash
bin/rails db:migrate
```
Write fixtures and model tests, then `bin/rails test`. **Don't start the GraphQL work until the model tests pass.**

## 3. Step 2: the type

`app/graphql/types/appointment_type.rb`
```ruby
module Types
  class AppointmentType < Types::BaseObject
    field :id, ID, null: false
    field :reason, String, null: true
    field :starts_at, GraphQL::Types::ISO8601DateTime, null: false
    field :patient, Types::PatientType, null: false
  end
end
```
Rules:
- One class per file. List every column the client may read, and **nothing else** (no `password_digest`, no internal flags).
- `null: false` only when the database column is `NOT NULL`.
- `ID` is serialized as a **string**.
- Columns are exposed in camelCase automatically (`starts_at` becomes `startsAt`).
- Dates: `GraphQL::Types::ISO8601Date`. Timestamps: `GraphQL::Types::ISO8601DateTime`.
- Add a back-reference like `patient` only if clients need it, and add the dataloader (section 7) when you do.

## 4. Step 3: queries

In `app/graphql/types/query_type.rb`:
```ruby
field :appointments, [ Types::AppointmentType ], null: false

def appointments
  Appointment.order(:starts_at)
end

field :appointment, Types::AppointmentType, null: true do
  argument :id, ID, required: true
end

def appointment(id:)
  Appointment.find(id)
end
```
Rules:
- **A list** returns `null: false` (an empty list is `[]`, never null).
- **A single record** returns `null: true`, so a missing record can be null with an error.
- Use `find`, not `find_by`. A missing record raises `RecordNotFound`, and the schema's `rescue_from` converts it into a `NOT_FOUND` error with a stable code.
- Always `order(...)` a list so the result is deterministic (and tests don't flake).

## 5. Step 4: mutations

All three inherit from `BaseMutation`, which gives you `user_errors_from(record)`.

### Create: `app/graphql/mutations/create_appointment.rb`
```ruby
module Mutations
  class CreateAppointment < BaseMutation
    null true

    argument :patient_id, ID, required: true
    argument :starts_at, GraphQL::Types::ISO8601DateTime, required: true
    argument :reason, String, required: false

    field :appointment, Types::AppointmentType
    field :errors, [ Types::UserErrorType ], null: false

    def resolve(**attrs)
      appointment = Appointment.new(attrs)

      if appointment.save
        { appointment: appointment, errors: [] }
      else
        { appointment: nil, errors: user_errors_from(appointment) }
      end
    end
  end
end
```

### Update: `update_appointment.rb`
```ruby
module Mutations
  class UpdateAppointment < BaseMutation
    null true

    argument :id, ID, required: true
    argument :starts_at, GraphQL::Types::ISO8601DateTime, required: false
    argument :reason, String, required: false

    field :appointment, Types::AppointmentType
    field :errors, [ Types::UserErrorType ], null: false

    def resolve(id:, **attrs)
      appointment = Appointment.find(id)

      if appointment.update(attrs)
        { appointment: appointment, errors: [] }
      else
        { appointment: nil, errors: user_errors_from(appointment) }
      end
    end
  end
end
```
Do **not** accept the parent's id (`patient_id`) on update. Moving a record to another parent can move data across tenants.

### Delete: `delete_appointment.rb`
```ruby
module Mutations
  class DeleteAppointment < BaseMutation
    null true

    argument :id, ID, required: true

    field :deleted_id, ID
    field :errors, [ Types::UserErrorType ], null: false

    def resolve(id:)
      appointment = Appointment.find(id)
      appointment.destroy!

      { deleted_id: id, errors: [] }
    end
  end
end
```
If the model has a `dependent: :restrict_with_exception` association (like `Organization` does), `destroy!` raises `ActiveRecord::DeleteRestrictionError`. Rescue it and return a user error with `code: "CONFLICT"` (see `delete_organization.rb`).

### Rules for every mutation
| Rule | Why |
|---|---|
| `null true` at the top of the class | a top-level error (like not found) can then null only this field, not the whole `data` |
| `field :thing` (no `null: false`) in the payload | on validation failure you return `nil`, and a non-null field would drop the whole response |
| `field :errors ... null: false` | clients can always loop over it |
| `save` / `update`, **not** `save!` / `update!` | they return `false`, so you can build the error list |
| `**attrs` | collects the keyword arguments into a hash. The argument names must match the column names |
| The return hash keys match the payload field names | `{ appointment: ..., errors: [] }` |

## 6. Step 5: register

`app/graphql/types/mutation_type.rb`
```ruby
field :create_appointment, mutation: Mutations::CreateAppointment
field :update_appointment, mutation: Mutations::UpdateAppointment
field :delete_appointment, mutation: Mutations::DeleteAppointment
```
Queries are registered by writing the `field` in `QueryType` (step 3). **A mutation file that isn't registered here does nothing.**

## 7. Step 6: relationships and N+1

Any field that reaches into an association from a list is a potential N+1. Use the dataloader:

```ruby
# in the PARENT type: has_many
def appointments
  dataloader.with(GraphQL::Dataloader::ActiveRecordAssociationSource, :appointments).load(object)
end

# in the CHILD type: belongs_to
def patient
  dataloader.with(GraphQL::Dataloader::ActiveRecordSource, Patient).load(object.patient_id)
end
```
See [guide 04](guide-04-patients-and-n-plus-one.md) for what N+1 is and why this fixes it. Prove it with a query-count test (section 9).

## 8. Step 7: errors, which kind where

| Situation | How | Client sees |
|---|---|---|
| Validation fails (blank, duplicate, bad format) | return `errors: user_errors_from(record)` | `errors { message path code }` in the payload, `code: "VALIDATION_FAILED"` |
| Business conflict (can't delete, state not allowed) | rescue and return a user error with a code like `"CONFLICT"` | the same shape, `code: "CONFLICT"` |
| Record not found | let `find` raise. The schema's `rescue_from` handles it | top-level `errors` with `extensions.code = "NOT_FOUND"` |
| Not logged in, not allowed (coming in steps 5 and 7) | raise `GraphQL::ExecutionError` with an `extensions` code | top-level error |
| Bad input type (wrong date, missing required argument) | nothing, GraphQL validates it | top-level error before your code runs |
| Unexpected bug | nothing, let it raise | a 500 in development, an error report in production |

Rule: **expected user mistakes are data, broken requests are top-level errors.** Clients switch on `code`, never on the message text.

## 9. Step 8: tests

Mutation and query tests go through the schema directly (fast, no HTTP):

```ruby
def execute(query, variables: {})
  CaresyncApiSchema.execute(query, variables: variables, context: {}).to_h
end
```
Cover these cases for **every** operation:

| Operation | Cases |
|---|---|
| list | returns all, in the expected order |
| one | found, unknown id gives `NOT_FOUND` |
| create | valid (count +1), invalid (count unchanged, `VALIDATION_FAILED`, correct `path`), duplicate if unique |
| update | valid (check `record.reload`), invalid (record unchanged), unknown id |
| delete | valid (count -1, `deletedId` returned), blocked by a dependency (`CONFLICT`), unknown id |

Habits that make tests worth having:
- Check the **database** (`assert_difference`, `reload`), not just the response.
- For not-found cases, also assert `assert_not_nil result["data"]` so you notice if `null true` is missing.
- Pass ids as **strings** (`record.id.to_s`).

Query-count test for relationships:
```ruby
def count_queries
  count = 0
  counter = ->(*, payload) { count += 1 unless payload[:name] == "SCHEMA" || payload[:cached] }
  ActiveSupport::Notifications.subscribed(counter, "sql.active_record") { yield }
  count
end
```
Create several parents with children, run the query, and `assert_equal 2, count_queries { ... }` (one for parents, one batched for children). It fails if someone reintroduces N+1.

## 10. Step 9: verify and commit

```bash
bin/rails test && bin/rubocop && bin/brakeman -q
bin/rails runner "puts CaresyncApiSchema.to_definition" | grep -i appointment   # schema loads, names are right
```
Then try each operation once in the sandbox (`/sandbox`) or Postman.

Commit message prefixes: `feat:` (new capability), `fix:`, `update:`, `chore:`, `test:`. Suggested split: `feat: add appointment model`, `feat: add appointment queries and mutations`, `test: ...`.

## 11. Naming conventions at a glance

| Thing | Ruby | GraphQL (client sees) |
|---|---|---|
| Model | `Appointment` | type `Appointment` |
| Type class | `Types::AppointmentType` | `Appointment` (the `Type` suffix is dropped) |
| Query field | `field :appointment` | `appointment` |
| Mutation class | `Mutations::CreateAppointment` | `createAppointment`, input `CreateAppointmentInput`, payload `CreateAppointmentPayload` |
| Argument | `starts_at` | `startsAt` |
| Mutation call | | `createAppointment(input: { ... })` |

## 12. Mistakes we've already made (so you can skip them)

| Mistake | Symptom | Fix |
|---|---|---|
| A hash with a comma where a colon belongs: `{ organization: nil, errors, user_errors_from(x) }` | `SyntaxError`, a 500 on `/graphql`, an empty sandbox | `errors: user_errors_from(x)` |
| One colon in `Types:UserErrorType` | `SyntaxError` | `Types::UserErrorType` |
| Copy-pasted a mutation and left the old class name | `expected file ... to define constant ..., but didn't` | rename the class to match the file |
| Copied `create` into `update` and kept `Model.new` and `save` | creates a new record instead of updating | `find`, then `update(attrs)` |
| Forgot `argument :id` on a field whose method takes `id:` | `ArgumentError` | declare the argument |
| `rescue_from` block with the wrong parameter names (`_err` but used `err`) | `NameError` when the error path runs | `|err, _obj, _args, _ctx, _field|` |
| Mutation not registered in `MutationType` | the mutation doesn't appear in the schema | add the `field ..., mutation:` line |
| Fixture label doesn't match the test (`one` vs `sunrise`) | `No fixture named ... found` | the label is the key in the YAML |

When the sandbox or Postman shows an empty schema, the cause is almost always a **file that doesn't load**. Read the **first line** of the error: it names the file and line.

## 13. Pull request checklist

- [ ] Model has `null: false`, foreign keys, indexes, and validations
- [ ] Type exposes only the fields clients may read
- [ ] List and single queries, using `find`
- [ ] Create, update and delete mutations, registered in `MutationType`
- [ ] Payload fields nullable, `errors` non-null, `null true` on each mutation
- [ ] Relationship fields use the dataloader, and a query-count test proves it
- [ ] Tests cover happy path, validation, not found and conflict for every operation
- [ ] `bin/rails test`, `bin/rubocop` and `bin/brakeman -q` are clean
- [ ] No tenant id taken from client input once tenancy exists, and no way to move a record between tenants
- [ ] Authorization applied (see below)
- [ ] Commits use the `feat:` / `fix:` / `update:` / `chore:` / `test:` prefixes

## 14. Security: what is not covered yet

At this point in the project there is **no authentication, tenancy or authorization**. Every query and mutation can read or change any record, so the app must not be deployed with real PHI.

Planned order (see [GRAPHQL-ROADMAP.md](../GRAPHQL-ROADMAP.md)): authentication (`context[:current_user]`), tenancy (`Current.organization`, scope every query to the user's organization), then roles and policies. When those land, update steps 3 to 5 of this guide: queries start from the user's organization (for example `current_organization.appointments`), create mutations take the organization from the logged-in user and not from input, and each operation calls an authorization check. Until then, treat the sections above as the "feature mechanics" only.

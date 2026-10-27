# Guide 04: Patients and the N+1 problem

Day 1 of the time-boxed plan in [GRAPHQL-ROADMAP.md](../GRAPHQL-ROADMAP.md). You implement it. This guide explains **why** first, then **what to type**.
Sources: [Dataloader overview](https://graphql-ruby.org/dataloader/overview.html), [Dataloader sources](https://graphql-ruby.org/dataloader/sources.html), and the installed gem's own code (`graphql` 2.6.12, `lib/graphql/dataloader/active_record_*_source.rb`).

Goal: `Patient` queries and mutations, and prove with a test that `organizations { patients { ... } }` runs a **constant** number of SQL queries.

Order matters. **Build the feature, measure the problem, then fix it.** That is how you learn to recognize N+1 in real codebases.

---

## 1. Concepts

### The N+1 problem, with a worked example

**One sentence:** N+1 is running one query per row in a loop, when a single query for all the rows would do.

Imagine the database has **3 organizations**, each with patients:

| Organization | Patients |
|---|---|
| Sunrise Clinic | Alice, Bob |
| Valley Health | Carol |
| Acme Care | Dan, Eve |

A client sends one query:

```graphql
{ organizations { name patients { firstName } } }
```
"Every organization, and for each one, its patients."

**Without the fix, Rails does this:**

Step 1, load the organizations. This is the **"1"**:
```sql
SELECT * FROM organizations;                          -- Sunrise, Valley, Acme
```

Step 2, GraphQL resolves the `patients` field on each organization, one at a time, and each runs `organization.patients`. These are the **"N"** (N = 3 here, because there are 3 organizations):
```sql
SELECT * FROM patients WHERE organization_id = 1;     -- Sunrise
SELECT * FROM patients WHERE organization_id = 2;     -- Valley
SELECT * FROM patients WHERE organization_id = 3;     -- Acme
```

**Total: 1 + 3 = 4 queries.** N extra queries on top of the first one, hence the name.

**Why it's a problem:** the count grows with the data, and every query is a round trip to the database.

| Organizations | Queries |
|---|---|
| 3 | 4 |
| 100 | 101 |
| 1,000 | 1,001 |

It feels fine in development with 3 rows, then crawls in production. It's the most common performance bug in GraphQL APIs.

**Node comparison:** it's `await db.query(...)` inside a `for` loop over rows:
```js
const orgs = await db.query('SELECT * FROM organizations');                 // 1
for (const org of orgs) {
  org.patients = await db.query('SELECT * FROM patients WHERE organization_id = ?', [org.id]);  // N
}
```

**With the dataloader**, each organization waits and asks together instead:

1. Sunrise says "I need my patients". The dataloader notes it and pauses that field.
2. Valley says the same. Noted.
3. Acme says the same. Noted.
4. Nobody else is left to ask, so the dataloader runs **one** query for all three:
   ```sql
   SELECT * FROM patients WHERE organization_id IN (1, 2, 3);
   ```
5. It splits the rows by `organization_id` and gives each organization its own patients.

**Total: 1 + 1 = 2 queries**, whether there are 3 organizations or 3,000. That's what "a constant number of queries" means: the count no longer grows with the data.

**See it yourself:** run the query in the sandbox with several organizations that have patients and watch the Rails server terminal. Without the fix there is one `SELECT ... patients WHERE organization_id = ?` line per organization. With the fix there is a single line with `IN (...)`. The test in section 3.2 counts these same statements.

**Quick check:** with 50 organizations, how many queries without the fix, and with it? (51 and 2.)

### How N+1 happens in plain Ruby (Rails and Active Record)

Active Record loads associations **lazily**: `organization.patients` doesn't query the database until the first time you use it, and it queries **once per organization object**.

```ruby
organizations = Organization.all          # 1 query
organizations.each do |org|
  puts org.patients.size                  # 1 query per org  -> N queries
end
```
Nothing looks wrong. Each line is correct, but the loop hides a query. This is why N+1 shows up in every Rails codebase, not only GraphQL.

**Ways to fix it in Rails:**

| Tool | What it does | Queries |
|---|---|---|
| `Organization.includes(:patients)` | loads the organizations, then all their patients together | 2 (or 1 with a join, when you filter on the association) |
| `Organization.preload(:patients)` | always 2 separate queries (`organizations`, then `patients WHERE organization_id IN (...)`) | 2 |
| `Organization.eager_load(:patients)` | one query with a `LEFT OUTER JOIN` | 1 (bigger result) |
| `joins(:patients)` | only for filtering or sorting. It does **not** load the patients | the N+1 stays |

```ruby
Organization.includes(:patients).each { |org| org.patients.size }   # 2 queries, however many organizations
```
Rule of thumb: use `includes` first, and `preload` when you want two plain queries.

**How to find N+1 in Rails:**
- Read `log/development.log`. A repeated `SELECT ... WHERE organization_id = ?` line is the sign.
- `strict_loading` makes lazy loading **raise**, which turns a silent N+1 into a loud error: `Organization.strict_loading.each { |o| o.patients.to_a }` raises `ActiveRecord::StrictLoadingViolationError`.
- The **Bullet** gem warns about N+1 in development (on the roadmap for later).
- A test that counts queries (section 3.2 below), which is what we'll do.

### How N+1 happens in GraphQL

GraphQL has the same lazy-loading problem, **plus a second one**: the client decides which fields to ask for, and each field resolves on its own.

```graphql
{ organizations { name patients { firstName } } }
```
1. The `organizations` field runs and returns a list of organizations.
2. graphql-ruby then walks the list. For **each** organization it calls the `patients` field method. Each call runs `organization.patients`, which is a lazy load and therefore its own query.
3. Each `patients` call is unaware of its siblings. Organization 1 doesn't know that organizations 2 and 3 are about to ask the same thing, so there's nowhere to batch them.

In REST you wrote one controller action and could simply add `.includes(:patients)` there, because **you** decided the response shape. In GraphQL the response shape is decided per query, so you can't know in advance whether patients will be asked for.

Why not `includes(:patients)` inside the `organizations` field?
- It would load patients for **every** request, even for `{ organizations { name } }`, where nobody asked for them (wasted work).
- It only helps one level. `patients { organization { name } }` is a second N+1 below it, and so on for every nested field.

**Ways to fix N+1 in GraphQL:**

| Approach | Idea | Verdict |
|---|---|---|
| **Dataloader** (`GraphQL::Dataloader`) | each field says "I need X for this record", the dataloader collects all requests at the same level and runs one batched query | **Standard solution, what we use** |
| `includes` at the root field | preload everything up front | wasteful and only one level deep |
| Lookahead (`extras: [:lookahead]`) | the root field checks which sub-fields were requested, then calls `includes` only for those | works, but you have to keep it in sync with the query shape by hand |
| `batch-loader` gem | the same batching idea as a separate library | not needed, the dataloader is built into graphql-ruby |

The dataloader pattern comes from Facebook's original **DataLoader** (the same idea as the `dataloader` npm package you may have used with Apollo). If you've used it in Node, the Ruby version works the same way: collect keys, run one batched fetch, hand back results in order.

**In one line:** in plain Rails you fix N+1 by loading associations up front with `includes`. In GraphQL you fix it by **batching** them with the dataloader, because you can't know the shape of the query in advance.

### The fix: the dataloader
`GraphQL::Dataloader` (already enabled in your schema with `use GraphQL::Dataloader`) **collects** all the "I need patients for organization X" requests that happen at the same level of the query, then runs **one** query for all of them.

```
Without: org1 -> query, org2 -> query, org3 -> query
With:    org1, org2, org3 -> wait ... -> ONE query for all three
```
Why not just `Organization.includes(:patients)` in the query field? Because it would load patients **even when the client didn't ask for them**, and it doesn't help for fields deeper in the tree. The dataloader loads only what the query actually requests.

### Built-in sources (verified in your installed gem)
graphql-ruby 2.6.12 ships two ActiveRecord sources, so we don't write our own:

| Source | Use it for | Call |
|---|---|---|
| `GraphQL::Dataloader::ActiveRecordAssociationSource` | `has_many` / `belongs_to` of records you already have | `dataloader.with(GraphQL::Dataloader::ActiveRecordAssociationSource, :patients).load(organization)` |
| `GraphQL::Dataloader::ActiveRecordSource` | find records by id (or another column) | `dataloader.with(GraphQL::Dataloader::ActiveRecordSource, Organization).load(id)` |

(The docs pages don't mention these two, but the gem's code does. We rely on the code.) Under the hood, the association source uses Rails' own `Preloader`, the same thing `includes` uses.

### `object` and `dataloader` inside a type
In a type class, `object` is the underlying record (an `Organization` inside `OrganizationType`), and `dataloader` is available to every field method.

---

## 2. Build the feature

### 2.1 Patient query
In `app/graphql/types/query_type.rb`:
```ruby
field :patient, Types::PatientType, null: true do
  argument :id, ID, required: true
end

def patient(id:)
  Patient.find(id)
end
```
Not found uses the schema's `rescue_from`, which gives the same `NOT_FOUND` as organizations.

### 2.2 Patient mutations
Three files in `app/graphql/mutations/`, same shape as the organization ones. Then register them in `Types::MutationType` as `create_patient`, `update_patient`, `delete_patient`.

**`create_patient.rb`**
```ruby
module Mutations
  class CreatePatient < BaseMutation
    null true

    argument :organization_id, ID, required: true
    argument :first_name, String, required: true
    argument :last_name, String, required: true
    argument :date_of_birth, GraphQL::Types::ISO8601Date, required: true

    field :patient, Types::PatientType
    field :errors, [ Types::UserErrorType ], null: false

    def resolve(**attrs)
      patient = Patient.new(attrs)

      if patient.save
        { patient: patient, errors: [] }
      else
        { patient: nil, errors: user_errors_from(patient) }
      end
    end
  end
end
```
Why:
- `GraphQL::Types::ISO8601Date` accepts `"1990-04-12"` and rejects bad dates **before** your code runs (a GraphQL validation error).
- `resolve(**attrs)` collects all keyword arguments into a hash, so `Patient.new(attrs)` works because the argument names match the column names (`organization_id`, `first_name`...).
- A nonexistent `organization_id` fails the `belongs_to` validation, and the user sees `Organization must exist`. Notice the error's `path` is `["input", "organization"]` and the client sent `organizationId`. That small mismatch is fine for now.
- **Security note:** letting the client pass `organizationId` is **temporary**. After authentication and tenancy (days 2), the organization comes from the logged-in user, never from input, and this argument is removed.

**`update_patient.rb`**
```ruby
argument :id, ID, required: true
argument :first_name, String, required: false
argument :last_name, String, required: false
argument :date_of_birth, GraphQL::Types::ISO8601Date, required: false

def resolve(id:, **attrs)
  patient = Patient.find(id)

  if patient.update(attrs)
    { patient: patient, errors: [] }
  else
    { patient: nil, errors: user_errors_from(patient) }
  end
end
```
Why: the attributes are optional, so the client sends only what changed. GraphQL passes only the arguments the client provided, so `attrs` holds only those. Note there is **no** `organization_id` argument: a patient must never move between tenants.

**`delete_patient.rb`**: `argument :id`, payload `field :deleted_id, ID` plus `errors`. Use `Patient.find(id)`, `patient.destroy!`, return `{ deleted_id: id, errors: [] }`.
Decision to remember: this is a **hard delete**. For real PHI, soft delete (`discard`) is usually better, because records must be kept for years. It's an open decision in the roadmap. Don't build it today, just know it.

### 2.3 Patient tests
Write these before the N+1 fix, so the fix can't break behaviour:

`test/graphql/queries/patient_query_test.rb`: `patient(id:)` returns the record (check `firstName`, `dateOfBirth`), and an unknown id gives `NOT_FOUND`.

`test/graphql/mutations/patient_mutations_test.rb`:

| Case | Expect |
|---|---|
| create, valid | count +1, `errors: []` |
| create, blank first name | `VALIDATION_FAILED`, count unchanged |
| create, nonexistent organization | an error mentioning `must exist` |
| create, bad date string `"not-a-date"` | a top-level GraphQL error (variables are invalid), no record created |
| update, change last name only | changed, first name untouched |
| update, unknown id | top-level `NOT_FOUND` |
| delete, existing patient | count -1, `deletedId` returned |

Run `bin/rails test`. All green means the feature works, with the N+1 still present.

---

## 3. Measure the N+1

### 3.1 Add `organization` to the patient type
In `PatientType`:
```ruby
field :organization, Types::OrganizationType, null: false
```
(No method yet. The default resolver calls `patient.organization`, which is another N+1.) Run the full query in the sandbox:
```graphql
{ organizations { name patients { firstName organization { name } } } }
```
and watch the Rails server terminal. You'll see one `SELECT ... patients` per organization. Thanks to the query log tags we installed, every SQL line is annotated with the GraphQL field that caused it (`current_graphql_field`), which makes the culprit easy to find.

### 3.2 Write a failing test that counts queries
Add a helper to the test (or to `test_helper.rb` if you want to reuse it):

```ruby
def count_queries
  count = 0
  counter = ->(*, payload) { count += 1 unless payload[:name] == "SCHEMA" || payload[:cached] }
  ActiveSupport::Notifications.subscribed(counter, "sql.active_record") { yield }
  count
end
```
`ActiveSupport::Notifications` is Rails' event bus. `sql.active_record` fires for every SQL statement, and we count the ones that aren't schema lookups or cache hits.

Test (`test/graphql/n_plus_one_test.rb`):
1. Create 3 extra organizations, each with one patient (so you have several organizations with patients).
2. Run `{ organizations { patients { firstName } } }`.
3. `assert_equal 2, count_queries { ... }`. That's one query for organizations plus one for all patients.

Run it. It **fails** with a bigger number (1 + the number of organizations). That's the point: red first.

---

## 4. Fix it with the dataloader

In `OrganizationType`:
```ruby
def patients
  dataloader.with(GraphQL::Dataloader::ActiveRecordAssociationSource, :patients).load(object)
end
```
In `PatientType`:
```ruby
def organization
  dataloader.with(GraphQL::Dataloader::ActiveRecordSource, Organization).load(object.organization_id)
end
```

Why it works:
- `with(Source, args)` picks (or creates) one source instance per unique argument set. All organizations asking for `:patients` share the same instance.
- `.load(object)` registers the request and pauses that field. When every field at this level has paused, the source runs `fetch` once with **all** the collected records.
- The association source then uses Rails' `Preloader`, so you get one `SELECT ... WHERE organization_id IN (...)`.
- The value returned for each record is the same one a plain `organization.patients` would give, so your existing tests still pass.

Run the N+1 test again: **green**, with exactly 2 queries. Add one more assertion for the patient `organization` path (ask for `patients { organization { name } }` and expect 3 queries: organizations, patients, organizations again by id).

---

## 5. Also notice: a cycle in the schema

`Organization -> patients -> organization -> patients -> ...`. A client can write a query that nests this 15 times (your `max_depth(15)` stops it there), and each level multiplies the work. That's why we also limit **complexity** in the hardening step. For now, know that adding back-references like `patient.organization` makes the schema **cyclic**, and cyclic schemas need limits.

## 6. Security reminder (HIPAA mindset)

`patient(id:)` and `organization { patients }` let anyone read any patient. That's acceptable only because the data is test fixtures and the app isn't deployed. Authentication (day 2) and tenancy fix who is allowed, and roles (day 3) fix what they may see.

---

## 7. Verify and commit

```bash
bin/rails test && bin/rubocop && bin/brakeman -q
```
Commits, in this order:
1. `feat: add patient query and mutations` (after the patient tests are green)
2. `test: add failing N+1 test` is optional. If you keep it as one commit, use `fix: avoid N+1 queries with dataloader`

---

## 8. Self-check (answers below)

1. What is the "N" and what is the "1" in N+1?
2. Why can't `includes(:patients)` in the `organizations` query field replace the dataloader?
3. What does `dataloader.with(Source, args)` group on?
4. In the delete test, why do we check the count and not just the response?
5. Why must `update_patient` have no `organization_id` argument?
6. Why does the N+1 test count queries and not measure time?
7. Which of the two sources do you use to load a record by id, and which for an association?

**Answers**
1. The "1" is the query that loads the parents (organizations). The "N" is one extra query per parent for its children.
2. `includes` would load patients even when the client didn't ask for them, and it doesn't help with fields deeper in the query. The dataloader loads only what the query requests.
3. On the source class plus its arguments. Same class and arguments means the same batch.
4. The response says "deleted", but only the count proves the row is gone. Check the database, not just the message.
5. Moving a patient between organizations would move PHI across tenants. Tenant identity must never be client-editable.
6. Time is noisy and depends on the machine. A query count is deterministic, so the test fails reliably when someone reintroduces N+1.
7. `ActiveRecordSource` for a record by id, `ActiveRecordAssociationSource` for an association of records you already hold.

---

## 9. What comes next

Guide 05 (day 2): **authentication**. `bcrypt`, a hashed API token table, `login` and `logout` mutations, and `context[:current_user]`.

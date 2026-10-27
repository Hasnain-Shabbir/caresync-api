# Guide 06: Multi-tenancy (tenant A must never see tenant B)

Day 2/3 of the time-boxed plan in [GRAPHQL-ROADMAP.md](../GRAPHQL-ROADMAP.md). You implement it. This guide explains **why** first, then **what to type**.
Sources: [Rails `CurrentAttributes`](https://api.rubyonrails.org/classes/ActiveSupport/CurrentAttributes.html), [Active Record associations](https://guides.rubyonrails.org/association_basics.html), [OWASP: Broken Object Level Authorization (API1)](https://owasp.org/API-Security/editions/2023/en/0xa1-broken-object-level-authorization/).

I have not run this guide's code. It builds on code that is already working (login, default-deny, patient and organization GraphQL). If a step doesn't behave as described, paste the output and I'll correct the guide.

Goal: every query and mutation only touches the **logged-in user's organization**. A user from Sunrise Clinic cannot read, change or even detect a patient from Valley Health. A test proves it.

---

## 1. Concepts

### What a tenant is here
An **Organization** is a tenant (a clinic). Every `User` and every `Patient` has an `organization_id`. Multi-tenancy means all those rows live in the same tables, and the code keeps each organization's rows apart.

### Authentication is not enough
After guide 05 the API knows **who** you are. Right now any logged-in user can still ask for `patient(id: 7)` and get the patient, even if patient 7 belongs to another clinic. This flaw has a name: **Broken Object Level Authorization** (OWASP API Security #1). In a HIPAA system it's a data breach: one logged-in user reads another clinic's PHI by changing an id.

### The rule that fixes it
**Never look a record up by id from the whole table. Always start from the user's organization.**

```ruby
Patient.find(id)                              # WRONG: any tenant's patient
current_organization.patients.find(id)        # RIGHT: only this tenant's patients
```
`current_organization.patients` adds `WHERE organization_id = <my org>` to every query. If the id belongs to another tenant, `find` raises `RecordNotFound`, the same as an id that doesn't exist at all.

### Return "not found", not "forbidden"
For another tenant's record we return the **same** `NOT_FOUND` as for a missing record. A "forbidden" answer would confirm that the record exists, which already leaks information. Our schema's `rescue_from RecordNotFound` already does this: nothing extra to write.

### Where the tenant comes from
From the **logged-in user** (`current_user.organization`), **never from client input**. This is why `createPatient` stops taking `organizationId`. A client-supplied tenant id is a client-controlled tenant.

### Three ways to enforce it
| Approach | How | Trade-off |
|---|---|---|
| **Explicit scoping** (we use this) | every resolver starts from `current_organization.patients` | easy to read and audit. You can forget one, which is why we add a safety-net test |
| `default_scope` | `Patient` always adds the tenant condition automatically | safe by default, but hidden magic. `unscoped`, joins and callbacks can bypass it or surprise you, and it is hard to debug |
| `acts_as_tenant` gem | the same idea packaged, with helpers | a dependency to learn, and more setup |
| Postgres Row-Level Security | the database refuses cross-tenant rows | the strongest, and more setup. A later defence-in-depth option |

We use explicit scoping for now: you see the `WHERE organization_id` in the code, and our tests check it.

---

## 2. Step by step

### 2.1 A helper: `current_organization`

In `app/graphql/concerns/authenticatable.rb` (the concern you already have), add:
```ruby
def current_organization
  current_user!.organization
end
```
Why: one place to ask "which tenant is this request for?". It calls `current_user!`, so an unauthenticated request still raises `UNAUTHENTICATED` first.

### 2.2 Scope the queries

In `app/graphql/types/query_type.rb`:

```ruby
def organizations
  Organization.where(id: current_organization.id).order(:name)
end

def organization(id:)
  Organization.where(id: current_organization.id).find(id)
end

def patient(id:)
  current_organization.patients.find(id)
end
```
Why each one:
- `organizations`: a tenant user must not list the other clinics. They see only their own, so the list has one item.
- `organization(id:)`: asking for any other id gives `NOT_FOUND`.
- `patient(id:)`: `current_organization.patients.find(id)` is the rule from section 1.

Optionally add a list so patients can be browsed:
```ruby
field :patients, [ Types::PatientType ], null: false

def patients
  current_organization.patients.order(:last_name, :first_name)
end
```

### 2.3 Scope the mutations

**`create_patient.rb`**: remove `argument :organization_id`, and build the patient from the user's organization:
```ruby
def resolve(**attrs)
  patient = current_organization.patients.new(attrs)
  ...
```
**`update_patient.rb`** and **`delete_patient.rb`**: replace `Patient.find(id)` with `current_organization.patients.find(id)`.

**`update_organization.rb`**: only your own organization:
```ruby
organization = Organization.where(id: current_organization.id).find(id)
```

**Open problem:** `createOrganization` and `deleteOrganization` are not tenant-level operations. A clinic's staff should not create or delete clinics. Creating organizations is a **platform-admin** job. We can't express that without roles, so guide 07 (roles) restricts them. Until then, they exist for every logged-in user. Treat that as a known gap, not a finished state.

### 2.4 Fixtures: a second tenant with a user and a patient

To prove isolation you need two tenants that both have users and patients. In `test/fixtures/users.yml` add a user for Valley Health (same hashed password as the others):
```yaml
admin_valley:
  organization: valley
  email: admin@valley.test
  encrypted_password: <%= Devise::Encryptor.digest(User, "password") %>
  first_name: Val
  last_name: Admin
  role: admin
```
In `test/fixtures/patients.yml` add a Valley patient:
```yaml
carol:
  organization: valley
  first_name: Carol
  last_name: Clark
  date_of_birth: 1978-01-22
```
Consequence: `valley` now has a user and a patient, so tests that **delete** `valley` (organization delete test) need a different organization to delete, or must create one. That's an expected ripple, and a good reminder that fixtures are shared state.

### 2.5 `Current` (optional, useful soon)

Rails has `ActiveSupport::CurrentAttributes`: a per-request global that Rails resets automatically for every request and job.
```ruby
# app/models/current.rb
class Current < ActiveSupport::CurrentAttributes
  attribute :user
  def organization = user&.organization
end
```
and in `GraphqlController#execute`, before running the query: `Current.user = current_user`. It lets code **outside** the resolvers (a mailer, a job, the audit log in the HIPAA step) know the tenant without passing it around. We don't need it for scoping today, because the resolvers already use `current_organization`. Add it if you want to see the pattern, and the audit log will use it.

### 2.6 Review: find every unscoped lookup

Search the GraphQL code for model calls that go straight to the table:
```bash
grep -rnE "(Patient|Organization|User)\.(find|find_by|where|all|first|last|order|exists)" app/graphql
```
Each hit is a potential leak. The ones that remain should be explained (for example `Organization.where(id: current_organization.id)`, or `User.find_for_database_authentication` in login, which has to be unscoped because nobody is logged in yet).

**A special case:** `GraphQL::Dataloader::ActiveRecordSource` loads records **by id with no tenant filter**. It's safe when the id comes from a record you've already scoped (like `patient.organization_id`), and unsafe if the id comes from client input.

### 2.7 Do not forget the REST API

`/api/v1/organizations` (the REST baseline) is **unauthenticated and unscoped**: anyone can list, create, change and delete organizations with no token at all. This is a bigger hole than anything in GraphQL. Before any deployment, either **delete those routes and the controller**, or put them behind authentication and scoping. The roadmap said REST stays as a comparison, so the decision is yours, but this API must not be reachable in production as it is.

---

## 3. Tests to write

The important tests are **cross-tenant**: log in as a user from one organization, and try to reach the other one's data.

| Case | Expect |
|---|---|
| `organizations` as a Sunrise user | only Sunrise is returned |
| `organization(id: <valley>)` as a Sunrise user | `data.organization` is null, `NOT_FOUND` |
| `patient(id: <carol, a Valley patient>)` as a Sunrise user | `NOT_FOUND` |
| `patient(id: <alice>)` as a Sunrise user | works |
| `patients` list as a Sunrise user (if you added it) | only Alice and Bob, never Carol |
| `updatePatient` on a Valley patient as a Sunrise user | `NOT_FOUND`, **and the patient is unchanged** (`reload`) |
| `deletePatient` on a Valley patient as a Sunrise user | `NOT_FOUND`, **and the count is unchanged** |
| `createPatient` | the patient's `organization` is the **user's** organization. Sending `organizationId` is rejected (an unknown argument) |
| `updateOrganization` on the other organization | `NOT_FOUND`, and the name is unchanged |
| the same checks reversed, as the Valley user | Valley sees only Valley data |
| unauthenticated request | still `UNAUTHENTICATED` (already tested) |

Write the cross-tenant tests so each one checks **both** the response and the database. A test that only checks the response can pass while the data was still changed.

Use `graphql_context(users(:admin_valley))` for the Valley user, and `graphql_context` (the Sunrise admin) by default.

**A safety-net test (optional, a good idea):** a test that fails if a new resolver uses an unscoped model lookup. It scans `app/graphql` for the pattern from 2.6 and checks hits against a short allowlist. It's a blunt tool, but it turns "remember to scope" into "the build fails if you forget". Say so if you want me to write it.

Also update the existing tests that break:
- `createPatient` tests that send `organizationId`: remove the argument, and remove the "nonexistent organization" case (it can't happen now).
- Organization **delete** tests: `valley` now has a user and a patient, so delete a freshly created organization instead.

---

## 4. Verify and commit

```bash
bin/rails test && bin/rubocop && bin/brakeman -q
```
Try it by hand in the sandbox: log in as two different users (create a Valley user in the console), and check that the second token cannot fetch the first organization's patient ids.

Suggested commits:
1. `feat: add current_organization helper`
2. `feat: scope organization and patient queries to the current organization`
3. `feat: scope patient and organization mutations to the current organization`
4. `test: add cross-tenant isolation tests`

---

## 5. Common mistakes

| Mistake | Why it hurts |
|---|---|
| `Patient.find(id)` in a new resolver | cross-tenant read or write |
| Accepting `organization_id` as input | the client chooses its own tenant |
| Returning "not allowed" for another tenant's record | confirms the record exists |
| Scoping the list but not the by-id lookup (or the reverse) | one door is still open |
| Testing only the response | the data might still have changed |
| Counting on the UI to hide it | GraphQL clients can send any query |

---

## 6. Self-check (answers below)

1. Why isn't authentication enough to protect PHI?
2. Why does a cross-tenant lookup return `NOT_FOUND` and not "forbidden"?
3. Why must the tenant come from `current_user` and never from input?
4. What does `current_organization.patients.find(id)` do differently from `Patient.find(id)`?
5. Why do the cross-tenant tests check the database as well as the response?
6. What is the risk of a dataloader source that loads by an id supplied by the client?
7. Why is the unauthenticated REST organizations API worse than a missing scope in GraphQL?

**Answers**
1. Authentication says who you are. It doesn't say which data is yours. A logged-in user could still read another clinic's records by changing an id.
2. "Forbidden" proves the record exists. `NOT_FOUND` looks identical to a record that doesn't exist.
3. Input is controlled by the caller, so they could choose any tenant. `current_user` comes from a verified token.
4. It adds `WHERE organization_id = <the user's organization>` to the query, so another tenant's id isn't found.
5. A response can say "not found" while a write still happened. The database check proves nothing changed.
6. A source like `ActiveRecordSource` loads by id with no tenant filter, so a client-supplied id could fetch another tenant's row.
7. It has no authentication at all, so anyone on the network can read, change and delete every organization without a token.

---

## 7. What comes next

Guide 07: **roles and policies**. `admin`, `provider`, `nurse`, `front_desk`: who may do what within an organization, and who may create or delete organizations at all. A role-by-action test matrix.

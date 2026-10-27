# Guide 07: Roles and policies (who may do what inside an organization)

Day 3 of the time-boxed plan in [GRAPHQL-ROADMAP.md](../GRAPHQL-ROADMAP.md). You implement it. This guide explains **why** first, then **what to type**.
Sources: [Pundit README](https://github.com/varvet/pundit) (gem 2.5.2), [HHS: HIPAA Security Rule summary](https://www.hhs.gov/hipaa/for-professionals/security/laws-regulations/index.html) (access control and the "minimum necessary" rule), [OWASP API Security: Broken Function Level Authorization (API5)](https://owasp.org/API-Security/editions/2023/en/0xa5-broken-function-level-authorization/).

I have not run this guide's code. I checked Pundit's README for the API names used here. Where the README doesn't confirm a detail (for example what the generated `ApplicationPolicy` returns by default), the guide says so and gives you a check.

Goal: inside one organization, what you may do depends on your **role**. A nurse can't delete patients. A front-desk user can't read clinical-level fields. Only the right role can rename an organization. Adding a new endpoint **without** deciding its permissions makes a test fail.

---

## 1. Concepts

### The three layers, and where we are
| Layer | Question | Status |
|---|---|---|
| Authentication | who are you? | done (guide 05) |
| Tenancy | whose data? | done (guide 06) |
| **Authorization** | **what may you do with it?** | **this guide** |

### Role-based access control (RBAC)
Every user has one role (the `User#role` enum already exists: `admin`, `provider`, `nurse`, `front_desk`). A **policy** answers "may this role do this action on this record?". Roles are the simplest model that fits most clinics. It's also what interviewers expect you to explain.

### Why Pundit
Pundit is the standard Rails authorization library. Its idea is small:
- A **policy** is a plain Ruby class, one per model (`PatientPolicy`), with a method per action (`update?`, `destroy?`). Each gets the **user** and the **record**.
- A policy can also define a **Scope**: which records the user may see at all.
- It's just Ruby, so it's easy to test without HTTP.

Pundit's README documents controller helpers (`authorize`, `policy_scope`), and the methods to call policies **outside** a controller: `Pundit.policy!(user, record)` and `Pundit.policy_scope!(user, Model)`. We aren't in a controller (we're in GraphQL resolvers), so we use those two directly and write a small helper around them.

### Default-deny
The most important rule in authorization: **if nobody said "allowed", the answer is "denied".** Every policy method returns `false` unless a role is listed. A forgotten rule then makes a feature unusable (a visible bug), not a data leak.

### 403 for roles, 404 for other tenants
- A user from **another organization** gets `NOT_FOUND`. We must not even confirm the record exists (guide 06).
- A user from the **same** organization who lacks the role gets `FORBIDDEN`. They already know the record exists, and a clear error helps them.

### The HIPAA idea behind field-level rules: "minimum necessary"
HIPAA expects people to access only the PHI they need for their job. In practice that means **role-specific fields**, not only role-specific actions. We'll show it with one field: a front-desk user can see a patient's name, but not the date of birth.

---

## 2. The permission matrix (decide this first)

Writing the matrix **before** the code is the real work. This one is a reasonable example, and you can adjust it. The mechanism stays the same.

| Operation | admin | provider | nurse | front_desk |
|---|---|---|---|---|
| list and view patients | yes | yes | yes | yes |
| see a patient's date of birth | yes | yes | yes | **no** |
| create a patient | yes | yes | no | yes |
| update a patient | yes | yes | yes | no |
| delete a patient | **yes** | no | no | no |
| view own organization | yes | yes | yes | yes |
| rename own organization | **yes** | no | no | no |
| create or delete an organization | nobody (see 3.7) | | | |

---

## 3. Step by step

### 3.1 Install Pundit

```bash
bundle add pundit
bin/rails generate pundit:install
```
The generator creates `app/policies/application_policy.rb`. **Open it and read it.** The README says only that it sets up "useful defaults", so verify that the query methods (`index?`, `show?`, `create?`, `update?`, `destroy?`) all return `false`. If any return `true`, change them to `false`. Restart the server afterwards (Rails picks up `app/policies/` only on restart).

Note: you don't include `Pundit::Authorization` anywhere. That module is for controllers, and we use the plain `Pundit.policy!` method.

### 3.2 `PatientPolicy`

`app/policies/patient_policy.rb`:
```ruby
class PatientPolicy < ApplicationPolicy
  def index?  = true            # any logged-in user may list patients
  def show?   = true
  def create? = user.admin? || user.provider? || user.front_desk?
  def update? = user.admin? || user.provider? || user.nurse?
  def destroy? = user.admin?

  # Field-level rule: minimum necessary.
  def view_date_of_birth? = !user.front_desk?
end
```
Why:
- `user` and `record` are provided by `ApplicationPolicy` (the generated file sets them in `initialize`).
- The role predicates (`user.admin?`) exist because `enum :role` on `User` creates them.
- Each rule is a single readable line, which makes it easy to check against the matrix.

### 3.3 `OrganizationPolicy`

```ruby
class OrganizationPolicy < ApplicationPolicy
  def show?   = true
  def update? = user.admin?
end
```
`create?` and `destroy?` stay `false` from `ApplicationPolicy` (default-deny). Nobody gets them, which matches the matrix.

### 3.4 One helper in the GraphQL concern

In `app/graphql/concerns/authenticatable.rb`, add:
```ruby
def authorize!(record, query)
  return true if Pundit.policy!(current_user!, record).public_send(query)

  raise GraphQL::ExecutionError.new("You are not allowed to do that", extensions: { code: "FORBIDDEN" })
end
```
Why:
- `Pundit.policy!(user, record)` finds `PatientPolicy` for a `Patient` (or for the `Patient` class itself), and raises if no policy exists. A missing policy is a **loud failure**, which is what we want.
- `public_send(query)` calls `update?` or `destroy?` on it.
- We raise the same kind of error as the rest of the API (`GraphQL::ExecutionError` with a stable `extensions.code`).
- `current_user!` is called first, so a request with no login still gets `UNAUTHENTICATED`.

### 3.5 Apply it in the resolvers and mutations

**Mutations** (call it **after** finding the record, so cross-tenant ids still give `NOT_FOUND` first):

```ruby
# create_patient.rb
def resolve(**attrs)
  authorize!(Patient, :create?)
  patient = current_organization.patients.new(attrs)
  ...

# update_patient.rb
patient = current_organization.patients.find(id)
authorize!(patient, :update?)

# delete_patient.rb
patient = current_organization.patients.find(id)
authorize!(patient, :destroy?)

# update_organization.rb
organization = Organization.where(id: current_organization.id).find(id)
authorize!(organization, :update?)
```
**Queries** (`index?` and `show?` are open to all roles, but call them anyway, so that a future change to the policy takes effect):
```ruby
def patients
  authorize!(Patient, :index?)
  current_organization.patients.order(:last_name, :first_name)
end

def patient(id:)
  record = current_organization.patients.find(id)
  authorize!(record, :show?)
  record
end
```
Order matters: **tenant check first (find), then role check (authorize!)**, so another tenant's record is never revealed by a different error.

### 3.6 Field-level: hide the date of birth

In `app/graphql/types/patient_type.rb`:
```ruby
field :date_of_birth, GraphQL::Types::ISO8601Date, null: true

def date_of_birth
  object.date_of_birth if Pundit.policy!(current_user!, object).view_date_of_birth?
end
```
Two changes you must notice: the field becomes **nullable** (`null: true`), because a front-desk user now gets `null`, and the method returns `nil` when the policy says no. Other fields are unchanged.

Think about what this **doesn't** do: it hides the value, but a client can still send the query, and it can't tell "hidden" from "empty". That's acceptable for this field. For stricter cases you'd raise `FORBIDDEN` instead.

### 3.7 Organizations: `createOrganization` and `deleteOrganization`

Creating or deleting a clinic isn't something clinic staff do. It's a **platform** operation. You have two options:

| Option | What it is | Verdict |
|---|---|---|
| **A: remove them from the API** | delete `create_organization.rb` and `delete_organization.rb` and their two `field` lines. Create tenants in the console, a seed script or an internal tool | **recommended for now**: smallest and safest, and nothing is exposed |
| B: a platform-admin flag | add a `platform_admin` boolean on `User`, add `create?` and `destroy?` rules to `OrganizationPolicy` | more to build, and a new kind of super-user to protect |

Whichever you pick, **delete the matching tests** (or update them), and delete the two organization mutations from the sections in the matrix test below.

### 3.8 Fixtures: two more roles

You have an `admin` and a `nurse` in Sunrise. Add the missing two to `test/fixtures/users.yml`, with the same password hash line as the others:
```yaml
provider_sunrise:
  organization: sunrise
  email: provider@sunrise.test
  encrypted_password: <%= Devise::Encryptor.digest(User, "password") %>
  first_name: Pat
  last_name: Provider
  role: provider

front_desk_sunrise:
  organization: sunrise
  email: frontdesk@sunrise.test
  encrypted_password: <%= Devise::Encryptor.digest(User, "password") %>
  first_name: Fran
  last_name: Desk
  role: front_desk
```
(Tests that count users per organization may need updating, the same ripple as when `admin_valley` was added.)

---

## 4. Tests

### 4.1 Policy tests (plain Ruby, no GraphQL, fast)

`test/policies/patient_policy_test.rb`: for each role, call the policy directly and check the matrix.

```ruby
policy = PatientPolicy.new(users(:nurse_sunrise), patients(:alice))
assert policy.update?
assert_not policy.destroy?
```
Write one test per row of the matrix (or loop over roles). Do the same in `organization_policy_test.rb`. Also test the defaults: a bare `ApplicationPolicy` denies everything.

### 4.2 GraphQL-level matrix test

`test/graphql/authorization_test.rb`. For every operation and role pair from the matrix, run the real GraphQL request as that user, and check `FORBIDDEN` or success.

| Case | Expect |
|---|---|
| nurse deletes a patient | `FORBIDDEN`, **and the patient still exists** |
| front_desk updates a patient | `FORBIDDEN`, **and the patient is unchanged** |
| nurse creates a patient | `FORBIDDEN`, and the count is unchanged |
| provider deletes a patient | `FORBIDDEN` |
| admin deletes a patient | works, count -1 |
| front_desk creates a patient | works |
| front_desk reads a patient | works, but `dateOfBirth` is `null` |
| nurse reads a patient | `dateOfBirth` is present |
| nurse renames the organization | `FORBIDDEN`, name unchanged |
| admin renames the organization | works |
| a user from **another** organization deletes a patient | `NOT_FOUND`, not `FORBIDDEN` |

Helper: `execute(query, variables:, as: users(:provider_sunrise))`, using `graphql_context(user)` (already in `test_helper.rb`).

### 4.3 A safety net: no endpoint without a decision

This is the point of default-deny, made into a test. Keep a list of every operation in the matrix test, and fail if the schema has one that's missing:

```ruby
test "every query and mutation in the schema is covered by the permission matrix" do
  in_schema = CaresyncApiSchema.mutation.fields.keys + CaresyncApiSchema.query.fields.keys
  in_schema -= %w[login]                      # public on purpose
  assert_equal [], in_schema - COVERED_OPERATIONS, "These operations have no permission test"
end
```
`COVERED_OPERATIONS` is an array of operation names you maintain in the test (`createPatient`, `updatePatient`, ...). Adding a mutation without adding it there makes the build fail, which forces someone to think about permissions.

---

## 5. Verify and commit

```bash
bin/rails test && bin/rubocop && bin/brakeman -q
```
Try it by hand: log in as a front-desk user in the sandbox, query a patient, and confirm `dateOfBirth` is `null`. Log in as a nurse and try `deletePatient`: you should get `FORBIDDEN`.

Suggested commits:
1. `chore: add pundit`
2. `feat: add patient and organization policies`
3. `feat: authorize queries and mutations with policies`
4. `feat: hide date of birth from front desk (minimum necessary)`
5. `chore: remove create and delete organization mutations` (if you pick option A)
6. `test: add policy tests and the permission matrix`

---

## 6. Common mistakes

| Mistake | Why it hurts |
|---|---|
| Checking the role **before** the tenant lookup | a user in another tenant gets `FORBIDDEN` for a record in another organization, which confirms the record exists |
| A policy method that returns `true` by default in `ApplicationPolicy` | forgotten rules silently allow everything |
| Checking permissions only in the UI | GraphQL clients can send any query |
| Forgetting `authorize!` in a new resolver | an endpoint with no role check. The matrix coverage test catches it |
| Testing only the response | a forbidden mutation might still have changed data. Check the record |
| Hiding a field in the type but exposing it in a nested query | check every path to the field |

---

## 7. Self-check (answers below)

1. What is the difference between authentication, tenancy and authorization?
2. What does default-deny mean, and how does it appear in `ApplicationPolicy`?
3. Why `FORBIDDEN` within an organization but `NOT_FOUND` across organizations?
4. Why do we find the record first and call `authorize!` second?
5. What does the "minimum necessary" rule mean for `dateOfBirth`?
6. Why is `date_of_birth` now `null: true`?
7. What does the coverage test protect against?

**Answers**
1. Authentication: who you are. Tenancy: whose data you may reach. Authorization: what you may do with it.
2. Anything not explicitly allowed is refused. `ApplicationPolicy`'s methods return `false`, and a policy grants a role by writing it into a method.
3. Within your own organization you already know the record exists, so a clear refusal helps you. Across organizations a different error would confirm the record exists.
4. So a cross-tenant id fails as `NOT_FOUND` first. Role checks must never leak that the record exists.
5. Each role gets only the PHI it needs, so front desk sees the name for scheduling but not the date of birth.
6. A hidden value returns `nil`, and a non-null field returning `nil` would make the whole parent null.
7. Someone adding an operation without deciding who may call it. The build fails until the matrix covers it.

---

## 8. What comes next

Guide 08: **password reset with a mailer and a background job**: ActionMailer, Solid Queue, Devise `recoverable`, and a `requestPasswordReset` and `resetPassword` mutation.

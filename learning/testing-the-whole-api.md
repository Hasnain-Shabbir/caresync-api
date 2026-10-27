# Testing the whole API by hand (data and a step-by-step check)

A manual test pack for everything built so far: GraphQL queries and mutations, login and logout, tenancy, roles and policies, field-level rules, and the N+1 fix. Run it in the sandbox (`http://localhost:4000/sandbox`) or Postman.

**What this covers:** the state of the project after guide 07 (policies). **What it doesn't:** the password-reset mailer, rate limiting and the README (not built yet).

The automated tests prove the same things in under 2 seconds (`bin/rails test`: 139 tests). Do this manual pass before a demo or a release, and when you want to see the behaviour with your own eyes.

---

## 0. Before you start

```bash
bin/rails server            # port 4000
```
Open `/sandbox`. For each request below, set **Variables** in the Variables panel and the token in the **Headers** panel (`Authorization: Bearer <token>`). Without the header, you're logged out.

Start from a clean development database (optional but easier to follow):
```bash
bin/rails db:reset          # drops, recreates and loads schema (development only!)
```
Careful: this **deletes all development data**.

---

## 1. Test data

Paste into `bin/rails console`. It's safe to run again (it uses `find_or_create_by!`).

```ruby
PASSWORD = "password-1234"   # at least 12 characters, because of Devise's password_length rule

sunrise = Organization.find_or_create_by!(name: "Sunrise Clinic")
valley  = Organization.find_or_create_by!(name: "Valley Health")

accounts = [
  [ sunrise, "admin@sunrise.test",     "Ada",  "Admin",    "admin" ],
  [ sunrise, "provider@sunrise.test",  "Pat",  "Provider", "provider" ],
  [ sunrise, "nurse@sunrise.test",     "Nina", "Nurse",    "nurse" ],
  [ sunrise, "frontdesk@sunrise.test", "Fran", "Desk",     "front_desk" ],
  [ valley,  "admin@valley.test",      "Val",  "Admin",    "admin" ]
]
accounts.each do |org, email, first, last, role|
  User.find_or_create_by!(email: email) do |u|
    u.assign_attributes(organization: org, password: PASSWORD, first_name: first, last_name: last, role: role)
  end
end

patients = [
  [ sunrise, "Alice", "Adams",  "1990-04-12" ],
  [ sunrise, "Bob",   "Brown",  "1985-09-30" ],
  [ sunrise, "Dan",   "Davis",  "2001-11-05" ],
  [ valley,  "Carol", "Clark",  "1978-01-22" ],
  [ valley,  "Eve",   "Evans",  "1995-07-18" ]
]
patients.each do |org, first, last, dob|
  Patient.find_or_create_by!(organization: org, first_name: first, last_name: last) { |p| p.date_of_birth = dob }
end

puts "Organizations: #{Organization.pluck(:id, :name).inspect}"
puts "Users:         #{User.pluck(:id, :email, :role).inspect}"
puts "Patients:      #{Patient.pluck(:id, :first_name, :organization_id).inspect}"
```
The last three lines print the **ids** you'll need. Note down the id of Valley Health, and of the patient **Carol** (a Valley patient) and **Alice** (a Sunrise patient).

### The accounts

All passwords are `password-1234`.

| Email | Organization | Role | Use it to test |
|---|---|---|---|
| `admin@sunrise.test` | Sunrise | admin | everything is allowed |
| `provider@sunrise.test` | Sunrise | provider | can create and update patients, can't delete |
| `nurse@sunrise.test` | Sunrise | nurse | can update, can't create or delete |
| `frontdesk@sunrise.test` | Sunrise | front_desk | can create, can't update, can't see date of birth |
| `admin@valley.test` | Valley | admin | the **other tenant**, for isolation checks |

### The permission matrix (what you should observe)

| Operation | admin | provider | nurse | front_desk |
|---|---|---|---|---|
| list and view patients | yes | yes | yes | yes |
| see `dateOfBirth` | yes | yes | yes | **null** |
| `createPatient` | yes | yes | **FORBIDDEN** | yes |
| `updatePatient` | yes | yes | yes | **FORBIDDEN** |
| `deletePatient` | yes | **FORBIDDEN** | **FORBIDDEN** | **FORBIDDEN** |
| `updateOrganization` (own) | yes | **FORBIDDEN** | **FORBIDDEN** | **FORBIDDEN** |

---

## 2. Authentication

### 2.1 Without a token
No header. Query:
```graphql
{ organizations { name } }
```
**Expect:** an error with `extensions.code` = `UNAUTHENTICATED`, and no data.

### 2.2 Login
Operation (this one works without a header):
```graphql
mutation($input: LoginInput!) {
  login(input: $input) { token user { id email role } errors { message path code } }
}
```
Variables:
```json
{ "input": { "email": "admin@sunrise.test", "password": "password-1234" } }
```
**Expect:** a `token` with three dot-separated parts, the user with `role: "admin"`, and `errors: []`. Copy the token into the Headers panel (`Authorization: Bearer <token>`).

### 2.3 Using the token
Run `{ organizations { name } }` again, **with** the header. **Expect:** `[{ "name": "Sunrise Clinic" }]`.

### 2.4 Wrong password and unknown email
Variables `{ "input": { "email": "admin@sunrise.test", "password": "wrong" } }`, then `{ "input": { "email": "nobody@sunrise.test", "password": "x" } }`.
**Expect:** `token: null`, and **the same** message and `INVALID_CREDENTIALS` code for both.

### 2.5 Lockout
Use `nurse@sunrise.test` with a wrong password **5 times**, then the right password.
**Expect:** the right password is now refused with `INVALID_CREDENTIALS` too. In the console: `User.find_by(email: "nurse@sunrise.test").access_locked?` is `true`. Unlock it: `User.find_by(email: "nurse@sunrise.test").unlock_access!`.

### 2.6 Logout
With the admin token in the header:
```graphql
mutation { logout(input: {}) { success } }
```
**Expect:** `success: true`. Now run `{ organizations { name } }` with the **same** header. **Expect:** `UNAUTHENTICATED`. Log in again to get a new token.

---

## 3. Queries and tenancy

Log in as `admin@sunrise.test` and set the header. Use the ids you noted.

| # | Operation | Expect |
|---|---|---|
| 3.1 | `{ organizations { id name } }` | only Sunrise, never Valley |
| 3.2 | `query($id: ID!) { organization(id: $id) { name } }` with Valley's id | `organization: null` and `NOT_FOUND` |
| 3.3 | `{ patients { firstName lastName } }` | Alice, Bob, Dan. **Never Carol or Eve** |
| 3.4 | `query($id: ID!) { patient(id: $id) { firstName } }` with Alice's id | Alice |
| 3.5 | the same with **Carol's** id | `patient: null` and `NOT_FOUND` |
| 3.6 | the same with id `0` | `NOT_FOUND` with the **same** message as 3.5 |
| 3.7 | `{ organizations { name patients { firstName } } }` | Sunrise with its three patients only |

3.5 and 3.6 giving the same error is deliberate: another tenant's record looks identical to a missing record.

Reverse check: log in as `admin@valley.test`. `{ patients { firstName } }` should show only Carol and Eve, and Alice's id should give `NOT_FOUND`.

---

## 4. Roles and the field-level rule

For each account, log in, set the header, and run the operations. Use the patient ids from section 1.

### 4.1 Field-level: date of birth
```graphql
query($id: ID!) { patient(id: $id) { firstName dateOfBirth } }
```
With Alice's id. **Expect:** `dateOfBirth` is `"1990-04-12"` for admin, provider and nurse, and **`null`** for `frontdesk@sunrise.test`.

### 4.2 Create
```graphql
mutation($input: CreatePatientInput!) {
  createPatient(input: $input) { patient { id firstName } errors { message path code } }
}
```
```json
{ "input": { "firstName": "Test", "lastName": "Created", "dateOfBirth": "2000-01-01" } }
```
**Expect:** works for admin, provider and front desk. **`FORBIDDEN`** (top-level error, `extensions.code`) for the nurse. There's no `organizationId` input: the patient is created in the **caller's** organization. Check in the console: `Patient.last.organization.name`.

### 4.3 Update
```graphql
mutation($input: UpdatePatientInput!) {
  updatePatient(input: $input) { patient { id lastName } errors { message path code } }
}
```
```json
{ "input": { "id": "<Alice's id>", "lastName": "Adamson" } }
```
**Expect:** works for admin, provider and nurse. **`FORBIDDEN`** for front desk.

### 4.4 Delete
```graphql
mutation($input: DeletePatientInput!) {
  deletePatient(input: $input) { deletedId errors { message code } }
}
```
```json
{ "input": { "id": "<id of the patient you created in 4.2>" } }
```
**Expect:** works for **admin only**. `FORBIDDEN` for provider, nurse and front desk, and the patient still exists afterwards (check in the console).

### 4.5 Update the organization
```graphql
mutation($input: UpdateOrganizationInput!) {
  updateOrganization(input: $input) { organization { name } errors { message path code } }
}
```
```json
{ "input": { "id": "<Sunrise's id>", "name": "Sunrise Clinic Group" } }
```
**Expect:** works for admin only, `FORBIDDEN` for the other roles. Rename it back afterwards.

### 4.6 Cross-tenant writes
As `admin@sunrise.test`, try `updatePatient` and `deletePatient` with **Carol's** id.
**Expect:** `NOT_FOUND` (not `FORBIDDEN`, because a user from another organization mustn't learn the record exists), and Carol is unchanged (`Patient.find_by(first_name: "Carol")` in the console).

### 4.7 Not part of the API
```graphql
mutation { createOrganization(input: { name: "X" }) { organization { id } } }
```
**Expect:** a validation error that the field doesn't exist. Same for `deleteOrganization`.

---

## 5. Validation errors (errors as data)

Logged in as admin:

| Operation | Variables | Expect |
|---|---|---|
| `createPatient` | `firstName: ""` | `patient: null`, `errors` with `code: "VALIDATION_FAILED"`, `path: ["input","firstName"]` |
| `createPatient` | `firstName: ""` and `lastName: ""` | **both** errors are returned together |
| `createPatient` | `dateOfBirth: "not-a-date"` | a **top-level** error (invalid variable), nothing created |
| `createPatient` | no `firstName` at all | a top-level error naming `firstName` |
| `updateOrganization` | `name: ""` | `VALIDATION_FAILED` and the name unchanged |

The first two show **errors as data** (inside the payload), and the last two show GraphQL rejecting the input before your code runs.

---

## 6. N+1 check

In a second terminal:
```bash
tail -f log/development.log | grep -E 'FROM "(organizations|patients)"'
```
Then run `{ organizations { name patients { firstName } } }` once (as admin).
**Expect:** a single `patients ... WHERE organization_id IN (...)` line, not one per patient. A tenant user sees one organization, so this check is limited: it confirms the dataloader batches, but it can't show the classic "one query per organization" pattern anymore.

---

## 7. Known gaps (expected to behave badly today)

| Check | Result today |
|---|---|
| `curl -i localhost:4000/api/v1/organizations` | **works without any token.** The old REST API is unauthenticated and unscoped. Remove or protect it before any deployment |
| a token after 30 minutes | rejected (absolute expiry). There's **no idle timeout** yet |
| 100 wrong logins from one IP | no rate limit yet (rack-attack not added) |
| password reset | not built yet |

---

## 8. The automated suite (the same checks, repeatable)

```bash
bin/rails test              # 139 tests, 0 failures expected
bin/rubocop                 # no offenses
bin/brakeman -q             # 0 warnings
```
By area:
```bash
bin/rails test test/models test/policies      # models and the permission matrix
bin/rails test test/graphql                   # queries, mutations, auth, tenancy, N+1
bin/rails test test/controllers               # HTTP: tokens, logout, expiry, REST
```

## 9. If something doesn't match

| Symptom | First thing to check |
|---|---|
| the sandbox shows no schema, or `/graphql` returns a 500 | `bin/rubocop` (syntax errors, by file and line), then `bin/rails runner "puts CaresyncApiSchema.to_definition"` |
| every request is `UNAUTHENTICATED` even with a token | the header must be exactly `Authorization: Bearer <token>`, and logout or 30 minutes may have killed it |
| `FORBIDDEN` for a role that should be allowed | `app/policies/patient_policy.rb` against the matrix in section 1 |
| `NOT_FOUND` for your own record | you may be using an id from another organization. Print ids with the console snippet |
| login says invalid credentials for a correct password | the account may be locked (`access_locked?`), or the password is under 12 characters at creation |

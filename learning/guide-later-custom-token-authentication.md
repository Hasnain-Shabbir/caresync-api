# Guide 05: Authentication (login, token, logout)

Day 2 of the time-boxed plan in [GRAPHQL-ROADMAP.md](../GRAPHQL-ROADMAP.md). You implement it. This guide explains **why** first, then **what to type**.
Sources: [Rails `has_secure_password`](https://api.rubyonrails.org/classes/ActiveModel/SecurePassword/ClassMethods.html), [graphql-ruby authorization and `ready?`](https://graphql-ruby.org/mutations/mutation_authorization), [OWASP Authentication cheat sheet](https://cheatsheetseries.owasp.org/cheatsheets/Authentication_Cheat_Sheet.html).

I have not run this end to end. Where I'm unsure of a detail, it says so. If something behaves differently, paste the output and I'll correct the guide.

Goal: a user logs in with email and password, gets a token, sends it in a header, and every query and mutation (except `login`) rejects requests without a valid token. Logout kills the token immediately.

---

## 1. Concepts

### Authentication vs authorization
- **Authentication:** who are you? (this guide)
- **Authorization:** what are you allowed to do? (guide 07: roles and policies)
- **Tenancy:** whose data can you see? (guide 06)

Right now the API has none of the three: anyone can read any patient. That's why the app can't be deployed yet.

### Why an opaque, database-backed token and not a JWT
| | Opaque token (we use) | JWT |
|---|---|---|
| What it is | a random string. The server looks it up in the database | a signed blob that carries the user's data |
| Revoke on logout | **instant**: mark the row revoked | hard: it stays valid until it expires, unless you keep a deny list (which is a database lookup again) |
| Idle timeout (HIPAA "automatic logoff") | easy: compare `last_used_at` | awkward |
| Cost | one indexed database lookup per request | none |

For PHI, instant revocation and idle timeout matter more than saving one lookup. You should still be able to explain the JWT trade-offs in an interview.

### Hash everything stored
- **Passwords:** `has_secure_password` stores a **bcrypt** hash in `password_digest` (the column already exists). bcrypt is deliberately slow, which makes guessing passwords expensive.
- **Tokens:** we store a **SHA-256** digest, not the token. If the database leaks, the digests can't be used to log in. SHA-256 (fast) is fine here, because a random 256-bit token can't be guessed, so we don't need a slow hash. It also lets us look the token up by digest.
- The plaintext token is shown to the client **once**, at login.

### Same error for "no such email" and "wrong password"
If the API said "email not found" for one and "wrong password" for the other, an attacker could discover which emails have accounts (user enumeration). We return the same message and code (`INVALID_CREDENTIALS`) for both.

### How the token travels
`Authorization: Bearer <token>` header on every request. The controller reads it and puts the user into GraphQL's `context`, where every resolver can read it. (We covered `context` in guide 02: it's `context = {}` in `GraphqlController`.)

---

## 2. Step by step

### 2.1 Install bcrypt

```bash
bundle add bcrypt
```
Why: `has_secure_password` needs it (the Rails Gemfile has it commented out).

### 2.2 Passwords on `User`

In `app/models/user.rb` add:
```ruby
has_secure_password
```
Why: it adds `password=` (a virtual attribute that writes `password_digest`), `authenticate(plain)` (returns the user or `false`), and validations (password required on create, at most 72 bytes).

**Update the user fixtures**, because `password_digest: "placeholder"` isn't a real bcrypt hash, so `authenticate` would never work. In `test/fixtures/users.yml`, for every user:
```yaml
password_digest: <%= BCrypt::Password.create("password", cost: BCrypt::Engine::MIN_COST) %>
```
`MIN_COST` keeps tests fast. Every fixture user now has the password `password`.

Check in the console: `User.first.authenticate("password")` returns the user.

### 2.3 The token table

```bash
bin/rails generate model ApiToken user:references token_digest:string expires_at:datetime last_used_at:datetime revoked_at:datetime
```
Edit the migration before running it:
- `t.string :token_digest, null: false`
- `t.datetime :expires_at, null: false`
- add `t.index :token_digest, unique: true`

Then `bin/rails db:migrate`.

Why each column:
| Column | Purpose |
|---|---|
| `token_digest` | SHA-256 of the token, unique, the lookup key |
| `expires_at` | absolute lifetime (for example 8 hours after login) |
| `last_used_at` | for the idle timeout (for example 15 minutes of inactivity) |
| `revoked_at` | set at logout. Non-null means dead |

### 2.4 The `ApiToken` model

```ruby
class ApiToken < ApplicationRecord
  ABSOLUTE_LIFETIME = 8.hours
  IDLE_TIMEOUT = 15.minutes

  belongs_to :user

  # Creates a token for the user. Returns [record, plaintext]. Only the digest is stored.
  def self.issue_for(user)
    plaintext = SecureRandom.urlsafe_base64(32)
    record = create!(
      user: user,
      token_digest: digest(plaintext),
      expires_at: ABSOLUTE_LIFETIME.from_now,
      last_used_at: Time.current
    )
    [ record, plaintext ]
  end

  def self.digest(plaintext)
    Digest::SHA256.hexdigest(plaintext)
  end

  # Returns the live token record for a plaintext token, or nil.
  def self.authenticate(plaintext)
    return nil if plaintext.blank?

    token = find_by(token_digest: digest(plaintext))
    return nil unless token&.active?

    token.update_column(:last_used_at, Time.current)
    token
  end

  def active?
    revoked_at.nil? && expires_at.future? && last_used_at > IDLE_TIMEOUT.ago
  end

  def revoke!
    update!(revoked_at: Time.current)
  end
end
```
Why:
- `SecureRandom.urlsafe_base64(32)` gives 256 bits of randomness, which is not guessable.
- `active?` is the single place that decides "is this token still good": not revoked, not past its absolute expiry, and used within the idle window.
- `update_column` skips validations and callbacks, because we only want to bump the timestamp.
- Writing `last_used_at` on every request is a database write per request. It's fine for us. (At scale you'd update it at most once a minute.)

Also add `has_many :api_tokens, dependent: :destroy` to `User`. Decision for you: `:destroy` is right for tokens (they're disposable), unlike patients.

### 2.5 Read the header in the controller

In `app/controllers/graphql_controller.rb`, build the context from the token:
```ruby
context = {
  current_user: current_api_token&.user,
  current_token: current_api_token
}
```
and add a private method:
```ruby
def current_api_token
  return @current_api_token if defined?(@current_api_token)

  header = request.authorization.to_s
  plaintext = header.delete_prefix("Bearer ").presence if header.start_with?("Bearer ")
  @current_api_token = ApiToken.authenticate(plaintext)
end
```
Why:
- `request.authorization` is Rails' reader for the `Authorization` header.
- The `defined?` guard memoizes the result so the token is looked up once per request. `||=` wouldn't work because the result may legitimately be `nil`.
- A bad, expired or missing token doesn't return HTTP 401. It just means `current_user` is `nil`, and the resolvers decide. GraphQL convention is HTTP 200 with an error in the body.

### 2.6 One place that says "login required"

Create `app/graphql/concerns/authenticatable.rb`:
```ruby
module Authenticatable
  def current_user
    context[:current_user]
  end

  def current_user!
    current_user || raise(GraphQL::ExecutionError.new("Authentication required", extensions: { code: "UNAUTHENTICATED" }))
  end
end
```
(I believe Rails autoloads `app/graphql/concerns` the same way as `app/models/concerns`. If you get `uninitialized constant Authenticatable`, tell me.)

Include it:
- In `Types::BaseObject`: `include Authenticatable`
- In `Mutations::BaseMutation`: `include Authenticatable`

**Queries:** call it first in each resolver:
```ruby
def organizations
  current_user!
  Organization.order(:name)
end
```
Do the same in `organization(id:)` and `patient(id:)`.

**Mutations:** use graphql-ruby's `ready?` hook, which runs before `resolve`. In `BaseMutation`:
```ruby
def ready?(**_args)
  current_user!
  true
end
```
All mutations inherit it, so they're protected **by default**. That's the key design choice: new mutations are secure unless someone deliberately opts out. `login` overrides it:
```ruby
def ready?(**_args) = true
```
Why default-deny: forgetting a check shouldn't make an endpoint public.

### 2.7 The `login` mutation

`app/graphql/mutations/login.rb`:
```ruby
module Mutations
  class Login < BaseMutation
    null true

    argument :email, String, required: true
    argument :password, String, required: true

    field :token, String
    field :user, Types::UserType
    field :errors, [ Types::UserErrorType ], null: false

    def ready?(**_args)
      true
    end

    def resolve(email:, password:)
      user = User.find_by(email: email)&.authenticate(password)

      if user
        _record, plaintext = ApiToken.issue_for(user)
        { token: plaintext, user: user, errors: [] }
      else
        { token: nil, user: nil, errors: [ { message: "Invalid email or password", path: [ "input" ], code: "INVALID_CREDENTIALS" } ] }
      end
    end
  end
end
```
You also need `Types::UserType` (fields: `id`, `email`, `first_name`, `last_name`, `role`). **Do not expose `password_digest`.**

Why:
- `User.find_by(email:)&.authenticate(password)` is `nil` for an unknown email **and** for a wrong password, so there's one failure branch and one message.
- The plaintext token is returned **only here**, and is never stored.
- Always send the password as a GraphQL **variable**, never inline in the query text. Rails filters `password` out of the logs when it's a parameter, but a password written inside the query string would be logged.

### 2.8 The `logout` mutation

```ruby
module Mutations
  class Logout < BaseMutation
    null true

    field :success, Boolean, null: false

    def resolve
      context[:current_token].revoke!
      { success: true }
    end
  end
end
```
It needs no `ready?` override, because the default already requires a user. Register both in `Types::MutationType`: `field :login, mutation: Mutations::Login` and `field :logout, mutation: Mutations::Logout`.

### 2.9 Fix the existing tests (this will break them)

Once the checks are in, every existing test that sends `context: {}` gets `UNAUTHENTICATED`. Fix them in one place. In `test/test_helper.rb` add a shared helper to `ActiveSupport::TestCase`:
```ruby
def graphql_context(user = users(:admin_sunrise))
  { current_user: user }
end
```
and in each test file's `execute`, change `context: {}` to `context: graphql_context`. The request tests (`graphql_controller_test.rb`) need a real header. Log in once in `setup`:
```ruby
_record, token = ApiToken.issue_for(users(:admin_sunrise))
@headers = { "Authorization" => "Bearer #{token}" }
```
and pass `headers: @headers` to each `post graphql_url`.

---

## 3. Tests to write

`test/graphql/mutations/login_test.rb` and `test/graphql/auth_test.rb`:

| Case | Expect |
|---|---|
| login with the right password | a token string, `errors: []`, and an `ApiToken` row exists with a digest that isn't the token |
| login with a wrong password | `token` nil, `code: "INVALID_CREDENTIALS"` |
| login with an unknown email | the **same** message and code as the wrong password |
| the stored value is not the plaintext | `ApiToken.last.token_digest != token` |
| a query without a token | top-level `UNAUTHENTICATED`, `data` nil or the field nil |
| a mutation without a token | `UNAUTHENTICATED`, and **no record created** (`assert_no_difference`) |
| a request with a valid token (HTTP, `Authorization: Bearer`) | the query works |
| logout, then reuse the token | the second request is `UNAUTHENTICATED` |
| an expired token (`travel_to` past `expires_at`) | `UNAUTHENTICATED` |
| an idle token (`travel_to` 16 minutes later) | `UNAUTHENTICATED` |
| a revoked token | `UNAUTHENTICATED` |

`travel_to` is Rails' time machine. Wrap a test body in `travel_to(16.minutes.from_now) { ... }` to test timeouts without waiting. For the HTTP tests, use the integration style from `graphql_controller_test.rb`.

---

## 4. Try it in the sandbox

Login (variables, not inline):
```graphql
mutation($input: LoginInput!) {
  login(input: $input) { token user { id email role } errors { message code } }
}
```
```json
{ "input": { "email": "admin@sunrise.test", "password": "password" } }
```
(Your development database has no users yet. Create one in the console: `User.create!(organization: Organization.first, email: "me@example.com", password: "password", first_name: "Me", last_name: "Dev", role: "admin")`.)

Copy the `token`. In the sandbox's **Headers** panel, add:
```
Authorization: Bearer <paste the token>
```
Now `{ organizations { name } }` works. Remove the header, and it returns `UNAUTHENTICATED`. Run `logout`, and the same token stops working at once.

---

## 5. Security notes (HIPAA mindset)

- **Unique user ids and automatic logoff** are HIPAA technical safeguards. The idle timeout (`IDLE_TIMEOUT`) is the automatic logoff.
- **Passwords:** bcrypt, minimum length rule (add a `validates :password, length: { minimum: 12 }, allow_nil: true` when you want one).
- **Never log tokens.** Rails filters parameters named like `password` and `token`, but check `config/initializers/filter_parameter_logging.rb`. The `Authorization` header isn't logged by default.
- **Always use HTTPS in production** (`config.force_ssl = true`). A Bearer token over plain HTTP can be stolen.
- **Brute force:** login can be hammered with guesses until we add rate limiting (day 3 hardening, `rack-attack`). Until then, don't deploy.
- Deleting a user should delete their tokens (`dependent: :destroy`) so no token outlives its owner.

---

## 6. Verify and commit

```bash
bin/rails test && bin/rubocop && bin/brakeman -q
```
Suggested commits:
1. `chore: add bcrypt and secure password to User`
2. `feat: add api tokens (hashed, expiring, revocable)`
3. `feat: add login and logout mutations`
4. `feat: require authentication for all queries and mutations`
5. `test: send auth context in existing graphql tests`

---

## 7. Self-check (answers below)

1. Why store a SHA-256 digest of the token, and not the token itself?
2. Why SHA-256 for tokens but bcrypt for passwords?
3. Why is the same error returned for an unknown email and a wrong password?
4. Why do we default-deny in `BaseMutation#ready?` and have `Login` opt out?
5. Why is "no token" an HTTP 200 with an error, not a 401?
6. What does the idle timeout protect against, and where is it enforced?
7. Why must the password be a GraphQL variable and not written inside the query?

**Answers**
1. If the database leaks, the digests can't be used to log in.
2. A token is 256 random bits, so it can't be guessed and a fast hash is safe. A password is low entropy, so it needs a deliberately slow hash.
3. Otherwise an attacker can find out which emails have accounts (user enumeration).
4. New mutations are protected unless someone deliberately removes the check, so forgetting it fails safe.
5. GraphQL reports errors in the body and keeps HTTP 200 for "the request was processed". Clients switch on `extensions.code`.
6. A token left on an unattended device. `ApiToken#active?` compares `last_used_at` to `IDLE_TIMEOUT.ago` on every request.
7. Variables are parameters that Rails filters from the logs. A password inside the query text would be written to the log.

---

## 8. What comes next

Guide 06: **multi-tenancy**. Every query is scoped to the logged-in user's organization, so tenant A can never read tenant B (tested), and `createPatient` stops taking `organizationId` from the client.

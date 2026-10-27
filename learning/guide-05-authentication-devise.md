# Guide 05: Authentication with Devise (JWT, for a GraphQL API)

Day 2 of the time-boxed plan in [GRAPHQL-ROADMAP.md](../GRAPHQL-ROADMAP.md). You implement it. Decision (2026-10-20): we use **Devise** because the company uses it. The hand-built version (bcrypt plus our own token table) is kept for later in [guide-later-custom-token-authentication.md](guide-later-custom-token-authentication.md).

Sources: [Devise README](https://github.com/heartcombo/devise) (Devise 5.0.4 works with Rails 7 onwards), [devise-jwt README](https://github.com/waiting-for-dev/devise-jwt) (0.13.0), [warden-jwt_auth](https://github.com/waiting-for-dev/warden-jwt_auth).

**How sure am I?** The Devise and devise-jwt parts come from their READMEs. The pieces that connect Devise to a GraphQL mutation (calling the token encoder and revoking from a mutation) are **not in the READMEs**. They come from my knowledge of the gem's code, and I have not run them. Section 3 has "verification checkpoints" to confirm each one in a minute. If one fails, paste the output and I'll fix the guide.

Goal: log in with email and password and get a JWT, send it in `Authorization: Bearer`, have every query and mutation (except `login`) reject requests without a valid token, and make logout invalidate the token at once. Accounts lock after repeated wrong passwords.

---

## 1. Concepts

### What the pieces are
```
Devise (modules: login, lockout, password reset ...)
  runs on Warden (a Rack middleware that asks "who is this request?" using strategies)
    devise-jwt adds a strategy that reads  Authorization: Bearer <JWT>
      and a revocation strategy (what happens at logout)
bcrypt hashes the passwords (Devise uses it for you, in `encrypted_password`)
```
- **Devise:** a framework of ready-made modules. You switch on only the ones you need.
- **Warden:** the middleware that decides who the current user is. Devise is a layer on top of it.
- **devise-jwt:** makes Devise understand JWT bearer tokens, which suits an API.

### The module list we will use
| Module | Why we want it |
|---|---|
| `database_authenticatable` | email and password, bcrypt hashing, `valid_password?` |
| `validatable` | email format and uniqueness, password length |
| `lockable` | lock the account after N wrong attempts (brute-force defence) |
| `recoverable` | password reset by email (the mailer arrives on day 3) |
| `jwt_authenticatable` (devise-jwt) | read and verify the Bearer token |

Left out for now: `registerable` (we create users in the console and seeds), `confirmable`, `trackable`, `rememberable`, `timeoutable` (all aimed at browser sessions).

### Why Devise normally doesn't fit an API, and what we change
Devise assumes **cookie sessions and HTML pages**. For us:
- We don't use Devise's controllers or routes. **Login and logout are GraphQL mutations** that call Devise's model methods directly.
- We use a **token** instead of a cookie.
- The API-only app has no session middleware, which Devise may complain about (see 2.7).

### The JWT trade-off, and why we pick the allowlist
A JWT is a signed token that carries the user id and an expiry. The server can verify it without a database lookup, which is also its weakness: **you can't cancel it before it expires** unless you keep a list.

devise-jwt offers revocation strategies:

| Strategy | How it works | Verdict for us |
|---|---|---|
| `JTIMatcher` | one `jti` column on the user. A new login replaces it, so only one device stays logged in | logs people out when they log in elsewhere |
| `Denylist` | store revoked token ids. Everything else is valid until it expires | tokens are valid by default, which is the wrong default for PHI |
| **`Allowlist`** | store **every issued** token id. A token is valid only if its row exists | **we use this.** Deleting a row revokes it at once, and several devices can be logged in |
| `Null` | no revocation | never |

With the allowlist, a JWT is checked against the database on every request, so we get the same instant-revoke behaviour as an opaque token, while still using Devise's standard JWT format. That matters for HIPAA-style requirements.

**Known gap:** a JWT has only an absolute expiry (`exp`). **Idle timeout** ("log out after 15 idle minutes", a HIPAA automatic-logoff safeguard) isn't built in. Devise's `timeoutable` works on sessions, not tokens. For now we use a **short absolute lifetime** (say 30 minutes). The custom-token guide shows how to build a real idle timeout, and we'll revisit it then.

### Same error for "no such email" and "wrong password"
If the API said "email not found" for one and "wrong password" for the other, an attacker could discover which emails have accounts. We return one message and one code (`INVALID_CREDENTIALS`) for both. Locked accounts use the **same** message too, otherwise an attacker learns the account exists.

---

## 2. Step by step

### 2.1 Install

```bash
bundle add devise devise-jwt
bin/rails generate devise:install
```
`devise:install` creates `config/initializers/devise.rb`. It also prints some instructions (set `default_url_options`, add a root route). Read them. For an API only the mailer host matters (for password reset), and we'll set it in `config/environments/development.rb`:
```ruby
config.action_mailer.default_url_options = { host: "localhost", port: 4000 }
```
Ignore the instructions about a root route and flash messages.

### 2.2 Devise initializer settings

In `config/initializers/devise.rb` set:
```ruby
config.navigational_formats = []          # no redirects on failure (we are an API)
config.password_length = 12..128
config.lock_strategy = :failed_attempts
config.unlock_strategy = :time
config.maximum_attempts = 5
config.unlock_in = 1.hour
config.stretches = Rails.env.test? ? 1 : 12   # (the generated file already has this) bcrypt cost, low in tests so they are fast
```
(`navigational_formats = []` is a common API setting that I know from experience. The README doesn't mention it, so confirm login failures don't redirect.)

And the JWT block, in the same file:
```ruby
config.jwt do |jwt|
  jwt.secret = Rails.application.credentials.devise_jwt_secret_key
  jwt.expiration_time = 30.minutes.to_i
end
```
We don't set `dispatch_requests` or `revocation_requests`: those are for Devise's own controllers, and we issue and revoke tokens from mutations.

**The secret:** generate one and store it in credentials, **not** in git:
```bash
bin/rails secret                  # prints a long random string
bin/rails credentials:edit        # add:  devise_jwt_secret_key: <paste it>
```
The README says to use a value **different from** `secret_key_base`. In tests, if credentials can't be read on your machine, set the same key in `config/credentials/test.key` or fall back to an `ENV` value. Tell me if tests can't see it.

### 2.3 Change the `users` table to Devise's columns

Our table has `password_digest` (we prepared it for `has_secure_password`). Devise calls the column `encrypted_password`. **Both hold the same bcrypt hash format**, so rename it and keep existing hashes valid.

```bash
bin/rails generate migration AddDeviseToUsers
```
Edit it:
```ruby
class AddDeviseToUsers < ActiveRecord::Migration[8.1]
  def change
    rename_column :users, :password_digest, :encrypted_password

    # recoverable
    add_column :users, :reset_password_token, :string
    add_column :users, :reset_password_sent_at, :datetime
    add_index  :users, :reset_password_token, unique: true

    # lockable
    add_column :users, :failed_attempts, :integer, default: 0, null: false
    add_column :users, :unlock_token, :string
    add_column :users, :locked_at, :datetime
    add_index  :users, :unlock_token, unique: true
  end
end
```
Run `bin/rails db:migrate`. Why `rename_column` and not drop and add: any existing hashes keep working, and the migration is reversible.

### 2.4 The allowlist table

```bash
bin/rails generate model AllowlistedJwt jti:string aud:string exp:datetime user:references
```
Edit the migration:
```ruby
t.string :jti, null: false
t.string :aud
t.datetime :exp, null: false
t.references :user, null: false, foreign_key: { on_delete: :cascade }
...
add_index :allowlisted_jwts, :jti, unique: true
```
`on_delete: :cascade` means deleting a user deletes their tokens at the database level, so no token outlives its owner. Run `bin/rails db:migrate`.

The model `AllowlistedJwt` can stay empty (`belongs_to :user` is added by the generator).

### 2.5 The `User` model

```ruby
class User < ApplicationRecord
  include Devise::JWT::RevocationStrategies::Allowlist

  devise :database_authenticatable, :validatable, :lockable, :recoverable,
         :jwt_authenticatable, jwt_revocation_strategy: self

  belongs_to :organization
  # keep: enum :role, ... and normalizes ... and the name validations
end
```
Changes to the existing model:
- **Remove** `validates :email, presence/uniqueness/format`. `:validatable` already adds those, and keeping both gives duplicate error messages. Keep `validates :first_name, :last_name, presence: true`.
- Keep `enum :role` and `normalizes :email`.
- The allowlist module expects `has_many :allowlisted_jwts` (the generator's `user:references` creates the `belongs_to` side). Add `has_many :allowlisted_jwts, dependent: :destroy`.

Then run the **user model tests**. Some messages may change (for example the email-format message). Update the test expectations as needed. That's a normal part of switching a validation source.

### 2.6 Routes: the Devise mapping without Devise routes

In `config/routes.rb`:
```ruby
devise_for :users, skip: :all
```
Why: Devise needs this line to register the `:user` mapping (Warden scope), but `skip: :all` stops it from adding Devise's HTML and JSON routes. We use `/graphql` only.

### 2.7 The session middleware caveat

An API-only app has no session middleware, and Warden can raise something like `undefined method 'session'` when it looks for a stored user. The Devise README says "some issues may still arise" in API mode. If you see that error when you first authenticate, add these lines to `config/application.rb`:
```ruby
config.session_store :cookie_store, key: "_caresync_session"
config.middleware.use ActionDispatch::Cookies
config.middleware.use config.session_store, config.session_options
```
We still never *rely* on the session: the JWT strategy doesn't store the user in it (the devise-jwt README also describes a `skip_session_storage` option to be safe). Only add the lines **if the error appears**.

### 2.8 Put the user into GraphQL's `context`

In `GraphqlController#execute`:
```ruby
context = {
  current_user: current_user,
  token: bearer_token
}
```
and a private method:
```ruby
def bearer_token
  header = request.authorization.to_s
  header.delete_prefix("Bearer ").presence if header.start_with?("Bearer ")
end
```
`current_user` is Devise's controller helper. It runs Warden, whose devise-jwt strategy reads the Bearer token, verifies the signature and expiry, finds the user, and checks the allowlist. If the token is missing or bad, it returns `nil`.

If `current_user` isn't defined in your API controller, use this instead:
```ruby
def current_user
  request.env["warden"]&.authenticate(scope: :user)
end
```

### 2.9 One place that says "login required" (default-deny)

`app/graphql/concerns/authenticatable.rb`:
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
(I believe Rails autoloads `app/graphql/concerns`. If you get `uninitialized constant Authenticatable`, tell me.)

- Include it in `Types::BaseObject` and in `Mutations::BaseMutation`.
- Queries: call `current_user!` first in each resolver (`organizations`, `organization`, `patient`).
- Mutations: in `BaseMutation` add the `ready?` hook, which runs before `resolve`:
  ```ruby
  def ready?(**_args)
    current_user!
    true
  end
  ```
  Every mutation inherits it, so new mutations are **protected by default**. `Login` opts out.

### 2.10 The `login` mutation

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
      user = User.find_for_database_authentication(email: email)

      if user&.valid_for_authentication? { user.valid_password?(password) } && user.active_for_authentication?
        token, _payload = Warden::JWTAuth::UserEncoder.new.call(user, :user, nil)
        { token: token, user: user, errors: [] }
      else
        { token: nil, user: nil, errors: [ { message: "Invalid email or password", path: [ "input" ], code: "INVALID_CREDENTIALS" } ] }
      end
    end
  end
end
```
Why each part:
- `find_for_database_authentication` is Devise's way to find a user by email (applies `case_insensitive_keys`).
- `valid_for_authentication? { ... }` is Lockable's wrapper. It runs the block, and **counts a failed attempt** (and locks the account at the maximum) when the block returns false. A bare `valid_password?` would never lock anyone. It also returns false for an already-locked account.
- `active_for_authentication?` also returns false for a locked or unconfirmed account.
- `UserEncoder.new.call(user, :user, nil)` creates the JWT, and (with the allowlist) also **inserts the allowlist row** by calling `on_jwt_dispatch`. It returns `[token, payload]`.
- The failure branch is one message for all failures: unknown email, wrong password and locked account.
- You need `Types::UserType` (fields `id`, `email`, `first_name`, `last_name`, `role`). **Do not expose `encrypted_password`.**
- Always send the password as a GraphQL **variable**, never inline in the query.

### 2.11 The `logout` mutation

```ruby
module Mutations
  class Logout < BaseMutation
    null true

    field :success, Boolean, null: false

    def resolve
      payload = Warden::JWTAuth::TokenDecoder.new.call(context[:token])
      current_user.allowlisted_jwts.where(jti: payload["jti"]).delete_all

      { success: true }
    end
  end
end
```
Deleting the allowlist row makes that token invalid immediately. (Logging out everywhere is `current_user.allowlisted_jwts.delete_all`.)

Register both in `Types::MutationType`: `field :login, mutation: Mutations::Login` and `field :logout, mutation: Mutations::Logout`.

### 2.12 Fix fixtures and existing tests

In `test/fixtures/users.yml`, rename the key and use a real hash for every user:
```yaml
encrypted_password: <%= BCrypt::Password.create("password", cost: 4) %>
```
(If you later set a Devise `pepper`, hashes need the pepper too. We haven't.) Every fixture user's password is `password`.

Once auth is enforced, every existing test with `context: {}` gets `UNAUTHENTICATED`. Add one helper in `test/test_helper.rb` (inside `ActiveSupport::TestCase`):
```ruby
def graphql_context(user = users(:admin_sunrise))
  { current_user: user }
end
```
and change `context: {}` to `context: graphql_context` in every test's `execute`. The request tests need a real token: use devise-jwt's test helper.
```ruby
require "devise/jwt/test_helpers"   # in test_helper.rb

headers = Devise::JWT::TestHelpers.auth_headers({}, users(:admin_sunrise))
post graphql_url, params: {...}, as: :json, headers: headers
```
(The devise-jwt README says Devise's own `sign_in` helper does not work for this. Use the helper above.)

---

## 3. Verification checkpoints (do these as you go)

Checking each uncertain piece takes seconds and it's a good habit for any library.

| Check | Command | Expect |
|---|---|---|
| Devise sees the User | `bin/rails runner "puts User.devise_modules.inspect"` | includes `:database_authenticatable`, `:lockable`, `:jwt_authenticatable` |
| Hash works | `bin/rails runner "puts User.first&.valid_password?('password')"` (after creating a user with a password) | `true` |
| Encoder exists and its signature | `bin/rails runner "p Warden::JWTAuth::UserEncoder.instance_method(:call).parameters"` | three parameters (user, scope, aud) |
| Decoder exists | `bin/rails runner "p Warden::JWTAuth::TokenDecoder.instance_method(:call).parameters"` | one parameter |
| Read the real code | `bundle open warden-jwt_auth` | opens the gem's folder in your editor. Look at `lib/warden/jwt_auth/user_encoder.rb` and `token_decoder.rb` |
| Token is in the allowlist | after a login, `AllowlistedJwt.count` in the console | goes up by 1 |

If an encoder or decoder name differs from the guide, trust the gem's code and tell me.

---

## 4. Tests to write

| Case | Expect |
|---|---|
| login with the right password | a `token`, `errors: []`, and `AllowlistedJwt.count` +1 |
| login with a wrong password | `token` nil, `INVALID_CREDENTIALS` |
| login with an unknown email | the **same** message and code |
| 5 wrong passwords, then the right one | still `INVALID_CREDENTIALS` (the account is locked). `user.reload.access_locked?` is true |
| a query without a token | top-level `UNAUTHENTICATED` |
| a mutation without a token | `UNAUTHENTICATED`, and no record created (`assert_no_difference`) |
| an HTTP request with a valid token | the query works |
| logout, then reuse the same token | `UNAUTHENTICATED` |
| an expired token (`travel_to` 31 minutes later) | `UNAUTHENTICATED` |
| a token whose allowlist row was deleted | `UNAUTHENTICATED` |
| deleting a user | their `AllowlistedJwt` rows are gone |

`travel_to` is Rails' time machine: `travel_to(31.minutes.from_now) { ... }`.

---

## 5. Try it in the sandbox

Create a user in the console (development has none):
```ruby
User.create!(organization: Organization.first, email: "me@example.com", password: "a-long-password-123",
             first_name: "Me", last_name: "Dev", role: "admin")
```
(Password length must be 12 or more, because of `config.password_length`.)

Login (variables, not inline):
```graphql
mutation($input: LoginInput!) { login(input: $input) { token user { id email role } errors { message code } } }
```
```json
{ "input": { "email": "me@example.com", "password": "a-long-password-123" } }
```
Copy the `token`. In the sandbox's **Headers** panel add `Authorization: Bearer <token>`. Then `{ organizations { name } }` works. Remove the header, and you get `UNAUTHENTICATED`. Run `logout`, and the same token stops working at once. Try 5 wrong passwords and then the right one: the account stays locked for an hour (`user.unlock_access!` in the console unlocks it).

---

## 6. Security notes (HIPAA mindset)

- **Unique user ids and automatic logoff** are HIPAA technical safeguards. We have unique users and a 30-minute token lifetime. A real idle timeout is the known gap (see section 1).
- **Brute force:** Lockable locks after 5 failed attempts. `rack-attack` rate limiting (day 3) adds protection against many accounts being tried from one IP.
- **The JWT secret** lives in credentials, never in git. If it leaks, anyone can forge tokens. Rotate it by setting a new `secret` and moving the old one to `rotation_secret` (devise-jwt supports this).
- **HTTPS only** in production (`config.force_ssl = true`), otherwise the Bearer token can be stolen.
- **Never log tokens or passwords.** Check `config/initializers/filter_parameter_logging.rb`.
- **Uniform errors** for unknown email, wrong password and locked account.
- **Password reset (`recoverable`)** sends a link by email. The mailer is built on day 3, and the reset token must not appear in logs or job arguments.

---

## 7. Verify and commit

```bash
bin/rails test && bin/rubocop && bin/brakeman -q
```
Suggested commits:
1. `chore: add devise and devise-jwt`
2. `feat: switch User to devise with lockable and recoverable`
3. `feat: add jwt allowlist`
4. `feat: add login and logout mutations`
5. `feat: require authentication for all queries and mutations`
6. `test: send auth context in existing graphql tests`

---

## 8. Self-check (answers below)

1. What is the relationship between Devise, Warden and bcrypt?
2. Why do we call `valid_for_authentication? { ... }` instead of just `valid_password?`?
3. Why the allowlist strategy and not a denylist?
4. Why return the same error for an unknown email, a wrong password and a locked account?
5. What can't a JWT do by itself, and how does the allowlist fix that?
6. Why `devise_for :users, skip: :all`?
7. What is the idle-timeout gap, and why doesn't Devise's `timeoutable` fill it?
8. Why is the password sent as a GraphQL variable?

**Answers**
1. Devise is the framework of modules. It runs on Warden, the middleware that decides who the current user is. bcrypt is the hashing library Devise uses for passwords.
2. Lockable's wrapper counts failed attempts and locks the account. `valid_password?` alone never locks anyone.
3. A denylist treats every token as valid until it is listed, which is the wrong default for PHI. With an allowlist, a token is valid only while its row exists, so deleting it revokes it at once.
4. Different messages would let an attacker find out which emails have accounts (user enumeration).
5. A JWT can't be cancelled before it expires. The allowlist keeps a database row per token, so deleting the row revokes it.
6. It registers the `:user` mapping that Warden needs, without adding Devise's own routes and controllers, because we log in through `/graphql`.
7. A JWT only has an absolute `exp`. `timeoutable` works on cookie sessions, which we don't use. A real idle timeout needs a `last_used_at` check, which the custom token guide covers.
8. Rails filters parameters like `password` out of the logs. A password written inside the query text would be logged.

---

## 9. Later: the custom version

[guide-later-custom-token-authentication.md](guide-later-custom-token-authentication.md) builds the same thing by hand (`has_secure_password`, our own token table, and a real idle timeout). When you do it, compare: you will see exactly what Devise and devise-jwt do for you.

---

## 10. What comes next

Guide 06: **multi-tenancy**. Every query is scoped to the logged-in user's organization, so tenant A can never read tenant B (tested), and `createPatient` stops taking `organizationId` from the client.

# Guide 09: Hardening (logs, query limits, introspection, rate limiting, CORS)

You type the code. This guide explains **why** first, then **what to type**.
Sources I used: the **installed gem source** (graphql 2.6.12, activejob 8.1.4, solid_queue 1.7.0, solid_cache 1.0.10, rack-attack 6.8.0, rack-cors 3.0.0) and the repo. I did **not** open any web docs in this session. The links below are where to read more, not things I checked:
[GraphQL-Ruby complexity and depth](https://graphql-ruby.org/queries/complexity_and_depth.html), [GraphQL-Ruby introspection](https://graphql-ruby.org/schema/introspection.html), [rack-attack](https://github.com/rack/rack-attack), [rack-cors](https://github.com/cyu/rack-cors), [OWASP GraphQL Cheat Sheet](https://cheatsheetseries.owasp.org/cheatsheets/GraphQL_Cheat_Sheet.html).

## What I verified and what I did not

**Verified by running it (scratch scripts outside the repo, `git status` stayed clean):**
- The raw reset token **is** in the Active Job log lines today. `log_arguments = false` removes it.
- `filter_parameters` filters `variables` when it is a JSON object, but **not** credentials written inline in the `query` string, and **not** a string-typed `variables`. A proc filter fixes both.
- `disable_introspection_entry_points` makes `__schema` and `__type` fail (`__typename` still works).
- `max_depth`, `max_complexity`, and the list multiplier behave as written below (the numbers in this guide are real output).
- The rack-attack initializer below, in a standalone Rack app: throttle after the limit, body still readable by the app, alias batching blocked, per-email throttle, form-encoded bodies, custom 429 body.
- The rack-cors snippet, in a standalone Rack app.

**NOT run in the Rails app (you are the first to run these):**
- The Gemfile changes, the initializer inside Rails, and **every test in section 3**. They are written from the verified pieces but never executed here.
- `config.active_job.log_arguments = false` as a **config line** (I toggled `ActiveJob::Base.log_arguments` at runtime. The gem's own comment names the config key, and your test will confirm it).
- `config.solid_queue.preserve_finished_jobs` (the setting exists in the gem, I did not check that the config key maps to it).
- A boot in `production` (introspection is off in production). Manual check in step 2.
- `req.ip` behind a proxy (marked **CHECK** in step 3).

Goal: close the cheap holes before anyone calls this "HIPAA-style": no secrets in logs, no unbounded queries, no brute force on the three anonymous operations, and no schema browsing in production.

---

## 1. Why this guide exists (the short version)

| Problem | Express/Node comparison | What we do |
|---|---|---|
| Reset token and credentials end up in log files | Redacting in `morgan` or `pino` | `log_arguments = false` plus a proc in `filter_parameters` |
| One query can ask for huge or recursive data | `graphql-depth-limit`, `graphql-query-complexity` | lower `max_depth`, add list complexity, `max_complexity` |
| Anyone can download the whole schema | `introspection: false` in Apollo Server | `disable_introspection_entry_points` in production only |
| Unlimited password guesses and reset emails | `express-rate-limit` | `rack-attack` |
| Browser blocks the frontend | `cors` middleware | `rack-cors`, only if the frontend is a browser app on another origin |

Two things to remember before the steps:

- **Introspection off is not security.** It hides the map, it does not lock the doors. Policies (guide 07) and tenancy (guide 06) are the real controls. Introspection off only removes free reconnaissance.
- **CSRF is not our problem here.** We authenticate with an `Authorization: Bearer` header, not cookies. A malicious site cannot make the browser attach that header. (This is also why CORS is not a security control for us: it only tells browsers what they may read.)

---

## 2. Steps

### Step 1. Stop secrets from reaching the logs (the open item from guide 08)

**Finding (verified).** In `log/test.log` and `log/development.log` there are lines like:

```
Enqueued ActionMailer::MailDeliveryJob ... with arguments: "Devise::Mailer", "reset_password_instructions", "deliver_now", {args: [#<GlobalID ...User/4>, "peV8pusny5GRPANts4E6", {}]}
```

That string is the **raw reset token**. Cause: Active Job prints job arguments, and it does **not** use `filter_parameters` (I read `active_job/log_subscriber.rb`: it calls `format(arg).inspect`, no filter). The same line appears again at "Performing". Also the rendered mail body (with the link) is logged at **debug** level. Production defaults to `info` (your `production.rb`), so keep it there and never set `RAILS_LOG_LEVEL=debug` in production.

**Fix.** In `config/application.rb`, next to `config.x.frontend_url`:

```ruby
config.active_job.log_arguments = false
```

I suggest all environments, not only production: dev already writes the mail to `tmp/mails` (that is where you read the token now), so you lose nothing, and dev then behaves like production.

**Second finding (verified in config): the token also lives in the queue DB longer than I said in guide 08.** Solid Queue **keeps finished jobs for 1 day by default** (`preserve_finished_jobs: true`, `clear_finished_jobs_after: 1.day`), and your `recurring.yml` cleans them hourly. The job row holds the arguments, so the raw token stays readable in the queue database for up to a day, even after use. The token itself dies after 6 hours or first use, so the real window is the 6 hours after sending. Options:

1. **Accept and document** (my recommendation for now): internal DB, 6 hour expiry, single use. Write it in the README risk notes.
2. Strict: `config.solid_queue.preserve_finished_jobs = false` in `production.rb` (**CHECK**: not verified that this config key maps to the setting). Trade-off: you lose finished-job history for debugging.

**Redact credentials written inline in a query.** The log shows `variables` as `[FILTERED]` when the client uses variables (verified in your dev log). But a client that writes the password **inside the query text** is logged in clear, because `query` is just a string (verified):

```
mutation { login(input:{email:"a@b.c", password:"Secret123!"}) { token } }   <- logged as is
```

Add to `config/initializers/filter_parameter_logging.rb` as a **second, separate block below** the existing `filter_parameters += [ ... ]` (do not put these lines inside the existing array, or you get a syntax error unless you add a comma after `:cvc`):

```ruby
GRAPHQL_AUTH_OPERATION = /\b(login|requestPasswordReset|resetPassword)\b/

Rails.application.config.filter_parameters += [
  ->(key, value) { value.replace("[FILTERED]") if key == "query" && value.is_a?(String) && value.match?(GRAPHQL_AUTH_OPERATION) },
  ->(key, value) { value.replace("[FILTERED]") if key == "variables" && value.is_a?(String) }
]
```

Behavior (verified on the filter itself): auth queries are redacted everywhere the key appears (including the duplicate `graphql` key Rails adds), normal queries stay readable, the original params are untouched. The same regex is reused in step 3, so you may want one shared constant later (not needed now).

Also, `email` is already in `filter_parameters`, and the SQL log showed `[FILTERED]` for it. Good, nothing to do.

### Step 2. Depth, complexity, and introspection (in `CaresyncApiSchema`)

**Why the current limit is too loose.** `max_depth(15)` is already there. But `Organization.patients` and `Patient.organization` point at each other (a cycle), so a query can go `organizations { patients { organization { patients { ... } } } }`. Every trip around the cycle multiplies the output by the number of patients. I measured real growth with 4 patients: 155 bytes at one trip, 619 bytes at two, about x4 each trip. With 1000 patients that is x1000 each trip. Depth 15 allows about 7 trips.

**Why `max_complexity` alone does not help yet (verified).** Our lists are plain arrays, not connections. GraphQL-Ruby only multiplies by page size for connections, so for arrays complexity is just "number of fields". The same chain scored 4, 6, 8, 10: linear, blind to the fan-out. So we teach it: a list field costs `10 x (cost of its children) + 1`.

1. In `app/graphql/types/base_field.rb`, add a constant inside the class:

```ruby
LIST_COMPLEXITY = ->(_ctx, _args, child_complexity) { 10 * child_complexity + 1 }
```

2. Use it on the two lists that grow with patient count:

```ruby
# organization_type.rb
field :patients, [ Types::PatientType ], null: false, complexity: Types::BaseField::LIST_COMPLEXITY

# query_type.rb
field :patients, [ Types::PatientType ], null: false, complexity: Types::BaseField::LIST_COMPLEXITY
```

`Query.organizations` stays plain on purpose: a tenant user always gets exactly one organization (guide 06).

3. In `app/graphql/caresync_api_schema.rb`, replace `max_depth(15)` and add the rest:

```ruby
max_depth(8)
max_complexity(200)
disable_introspection_entry_points if Rails.env.production?
```

**The numbers (verified output, 4 fields per patient):**

| Query | Result |
|---|---|
| `{ patients { id firstName lastName dateOfBirth } }` | complexity 41, allowed |
| `{ organizations { id name patients { 4 fields } } }` | complexity 44, allowed |
| organizations → patients → organization → `id` (one trip) | 22, allowed |
| two trips | 222, **blocked** (over 200) |
| four trips | depth 10, **blocked** (over 8) |

200 and 8 are my judgment, not a rule. Real queries here are depth 3 or 4. **Tune them against the queries your frontend actually sends**, and raise them only when a real query is rejected.

**Honest limit.** The proper fix for unbounded lists is **pagination** (connections with `first:` and a max page size). `patients` today returns every patient of the clinic in one response. That is also a data-exposure issue for PHI. It is not in the plan, so I am flagging it, not adding it.

**Introspection manual check (NOT run by me).** In production, `__schema` should fail. To check without a database:

```bash
RAILS_ENV=production SECRET_KEY_BASE_DUMMY=1 bin/rails runner 'puts CaresyncApiSchema.disable_introspection_entry_points?'
```

Expect `true`. (**CHECK**: it boots the production env locally. It should not need a database for this call, but I did not run it. If it complains, tell me the error.) Development keeps introspection on, so the Apollo Sandbox keeps working.

### Step 3. Rate limiting with rack-attack

**Why at the web layer.** `express-rate-limit` comparison: rack-attack is Rack middleware that runs **before** Rails, so a flood never reaches your code or the database.

**The GraphQL problem.** There is one URL, `POST /graphql`, so you cannot throttle "the login route". You must look **inside** the body for the operation. Also, rack-attack counts **HTTP requests**, not operations, so this one request tries 100 passwords:

```graphql
mutation { a: login(...) b: login(...) c: login(...) ... }
```

So we also **reject requests with more than one auth operation**. Devise `lockable` (5 failed attempts, 1 hour) is your backstop per account. Note the trade-off: lockable lets an attacker lock someone else out on purpose. The IP throttle keeps that cheap to do only slowly.

1. `Gemfile`: add `gem "rack-attack", "~> 6.8"`, then `bundle install`. (It installs its own Railtie that inserts the middleware, so **no** `config.middleware.use` line. I read the Railtie.)

2. Create `config/initializers/rack_attack.rb` (this exact code ran in my standalone test):

```ruby
class Rack::Attack
  AUTH_OPERATIONS = /\b(login|requestPasswordReset|resetPassword)\b/

  # Parse the GraphQL POST body once per request and remember it in the Rack env.
  def self.graphql_params(req)
    return {} unless req.post? && req.path == "/graphql"

    req.env["caresync.graphql_params"] ||=
      if req.media_type == "application/json"
        body = req.body.read
        req.body.rewind # Rails must still be able to read the body after us
        JSON.parse(body)
      else
        req.POST
      end
  rescue JSON::ParserError
    req.env["caresync.graphql_params"] = {}
  end

  def self.auth_operations(req)
    query = graphql_params(req)["query"]
    query.is_a?(String) ? query.scan(AUTH_OPERATIONS).flatten : []
  end

  # The email inside variables.input (the clients send variables as a JSON object).
  def self.input_email(req)
    variables = graphql_params(req)["variables"]
    email = variables.is_a?(Hash) ? variables.dig("input", "email") : nil
    email.to_s.strip.downcase.presence
  end

  # One HTTP request must not carry several auth operations (aliases would multiply attempts).
  blocklist("graphql/batched-auth") { |req| auth_operations(req).size > 1 }

  # 1. Per IP, for the three operations an anonymous caller can reach.
  throttle("auth/ip", limit: 10, period: 1.minute) do |req|
    req.ip if auth_operations(req).any?
  end

  # 2. Per email, so nobody can flood one person's inbox with reset mails.
  throttle("password-reset/email", limit: 3, period: 1.hour) do |req|
    input_email(req) if auth_operations(req) == [ "requestPasswordReset" ]
  end

  self.throttled_responder = lambda do |req|
    retry_after = (req.env["rack.attack.match_data"] || {})[:period].to_i
    [ 429,
      { "content-type" => "application/json", "retry-after" => retry_after.to_s },
      [ { errors: [ { message: "Too many requests", extensions: { code: "RATE_LIMITED" } } ] }.to_json ] ]
  end
end
```

What each piece does, in plain words:
- `graphql_params` reads the body in the middleware. Reading consumes it, so we `rewind` (my test confirmed the app still sees the body).
- `auth_operations` finds the operation names with a word-boundary regex. An alias like `a: login(...)` still contains the word `login`, so aliases do not hide it.
- A throttle counts only when its block returns a **non-nil key**. Returning `nil` means "not my request", so normal queries are never counted (verified).
- `retry-after` shows the **period**, an upper bound (the real wait may be shorter). Fine for a first version.
- The 429 body keeps your error shape (`extensions.code`) so the frontend can handle it like your other top-level errors. Clients see an HTTP 429, not 200, which is the normal convention for rate limits.

3. **CHECK: client IP.** `req.ip` is the Rack view of the IP. Behind a proxy (Kamal, Thruster) it may be the **proxy's** IP, which would put **all users in one bucket**. I could not test this. In production, log `req.ip` once for a real request and compare it with your own IP. If it is wrong, Rails' `request.remote_ip` handles trusted proxies better (available in the Rack env as `req.env["action_dispatch.remote_ip"]`), and we can switch the key to that.

4. **CHECK: the counter store.** rack-attack stores counters in `Rails.cache`. In production that is **Solid Cache** (a database table). It implements `increment` (I read it), but I did **not** verify it is atomic under concurrent requests, and each counted request becomes a DB write. Acceptable for three operations. For anything bigger, use Redis or memcached.

   In the **test** env the cache is `:null_store`: `increment` returns nil, rack-attack writes 1 each time, so counts never pass 1 and **nothing ever throttles in tests** (read from `cache.rb`, not run in Rails). So the test in section 3 swaps in a memory store.

Not covered by this step: a very large request body is read into memory by the middleware. `max_query_string_tokens(5000)` limits the **parsed** query, not the raw body. Mention it in the README as a known gap (a body size limit usually lives at the proxy).

### Step 4. CORS (decide, do not add by default)

You do **not** need CORS if the only callers are servers, curl, Postman, or the Apollo Sandbox. You need it only when a **browser app on another origin** calls the API. Your `FRONTEND_URL` default (`http://localhost:3000`) suggests a browser frontend, so it is likely, but it is your call.

Status: `config/initializers/cors.rb` is fully commented out, and `rack-cors` is **not** in your Gemfile (checked `Gemfile.lock`). Because we send an `Authorization` header, browsers send a **preflight** `OPTIONS` request first. With no CORS config the browser blocks the real request.

If you add it: `gem "rack-cors"`, then in `config/initializers/cors.rb`:

```ruby
Rails.application.config.middleware.insert_before 0, Rack::Cors do
  allow do
    origins Rails.configuration.x.frontend_url
    resource "/graphql", headers: %w[Authorization Content-Type], methods: %i[post options], max_age: 600
  end
end
```

My standalone test of this config: the allowed origin gets `access-control-allow-origin` and `authorization,content-type` allowed. Another origin gets **no** allow header. Rules: never `origins "*"` with a PHI API, and one explicit origin, not a list from user input. `insert_before 0` puts it first so the preflight is answered before anything else. (Not run inside Rails.)

### Step 5. The `filter_parameters` check, summarized

| Where | Before | After |
|---|---|---|
| `variables` as JSON object | filtered by key (`password`, `email`, `token`) | same |
| `query` with inline credentials | **logged in clear** | `[FILTERED]` (auth operations only) |
| `variables` as a string | **logged in clear** | `[FILTERED]` |
| Active Job arguments | **token in clear** | not logged |
| Mail body in debug log | token in link | keep production at `info` |
| SQL log email | `[FILTERED]` | same |

---

## 3. Tests

I did not run any of these. Put them in the places named below. Write them first if you want, they define the behavior.

**A. Logs: `test/graphql/log_hygiene_test.rb`**

1. **Job log does not contain the token.** I verified the technique in a scratch test: swap `ActiveJob::Base.logger` for a `StringIO` logger, run `requestPasswordReset` inside `perform_enqueued_jobs`, read the token from `ActionMailer::Base.deliveries.last.body.to_s[/token=([\w-]+)/, 1]`, and `assert_not_includes log, token`. Put the logger back in an `ensure`. (Include `ActiveJob::TestHelper`.) This test **fails before** step 1 and passes after, which proves the config line works.
2. **Inline credentials are redacted.** In an integration test, `post graphql_url, params: { query: 'mutation { login(input:{email:"a@b.c", password:"Secret123!"}) { token } }' }, as: :json`, then `assert_equal "[FILTERED]", request.filtered_parameters["query"]`. **CHECK**: `request.filtered_parameters` in integration tests is the thing I would try first. If it does not work as I expect, tell me.
3. **A normal query is not redacted**: same, with `{ patients { id } }`, expect the text unchanged.

**B. Limits: `test/graphql/query_limits_test.rb`** (validation errors come back before anything runs, so no dataloader setup is needed)

Build the repeated query with a small helper, same as my scratch runs:

```ruby
def trips(count)
  inner = "id"
  count.times { inner = "patients { organization { #{inner} } }" }
  "{ organizations { #{inner} } }"
end
```

1. `trips(1)` runs with no limit error (complexity 22).
2. `trips(2)` returns an error containing `exceeds max complexity` (222).
3. `trips(4)` returns an error containing `exceeds max depth` (depth 10).
4. A realistic query (`organizations { id name patients { id firstName lastName dateOfBirth } }`) runs with **no errors** as the admin from `graphql_context`. This one guards against setting the limits too tight.
5. **Coverage test, same idea as guide 07:** every list-of-objects field must have the multiplier, so a future `visits` or `notes` list cannot forget it.

```ruby
test "every list field of objects has a complexity multiplier" do
  exempt = %w[Query.organizations] # a tenant always sees one organization
  missing = CaresyncApiSchema.types.values
    .select { |t| t.kind.object? && !t.graphql_name.start_with?("__") && !t.graphql_name.end_with?("Payload") }
    .flat_map { |t| t.fields.values }
    .select { |f| f.type.list? && f.type.unwrap.kind.object? && !f.connection? }
    .reject { |f| f.complexity.is_a?(Proc) || exempt.include?(f.path) }
    .map(&:path)
  assert_empty missing, "Add complexity: Types::BaseField::LIST_COMPLEXITY to: #{missing.join(', ')}"
end
```

I ran this exact detection logic in a scratch script against your schema. With the multiplier in place it returns `[]`, and without it it lists the three list fields. (Mutation payload types are skipped because their lists are small error arrays.)

6. **Introspection** is only off in production, so a test cannot check the real setting. Test the mechanism instead, or just rely on the manual check in step 2. The mechanism: `Class.new(CaresyncApiSchema) { disable_introspection_entry_points }.execute("{ __schema { types { name } } }")` returns an error `Field '__schema' doesn't exist on type 'Query'` (verified), while the normal schema still answers. This tests GraphQL-Ruby more than your code, so it is optional.

**C. Throttling: `test/integration/rate_limit_test.rb`** (an `ActionDispatch::IntegrationTest`)

Setup and teardown matter here because rack-attack state is **class-level**:

```ruby
setup do
  Rack::Attack.cache.store = ActiveSupport::Cache::MemoryStore.new
  Rack::Attack.reset!
end

teardown do
  Rack::Attack.cache.store = Rails.cache # back to the null store, so other tests are never throttled
end
```

Cases (use a JSON `post graphql_url, params: { query: LOGIN, variables: { input: {...} } }, as: :json`):

1. **11th login from one IP in a minute returns 429**, the first 10 do not, and the 429 body has `extensions.code` `RATE_LIMITED`.
2. **A normal query is never counted**: send 15 `{ organizations { id } }` with a valid token, none returns 429.
3. **Two aliased logins in one request return 403.**
4. **4th `requestPasswordReset` for the same email returns 429**, even when you vary the email's case (`Victim@Example.com` vs `victim@example.com`). Different IPs are not possible in an integration test unless you pass `env: { "REMOTE_ADDR" => ... }`, so either do that or accept that this case also trips the IP limit.
5. **Your existing password-reset and auth tests still pass** (they call the schema directly, so they bypass the middleware, but run the whole suite to be sure).

Finish with `bin/rails test`, `bin/rubocop`, `bin/brakeman -q`.

---

## 4. Self-check (try first, answers below)

1. Why does the Active Job log show the token even though `:token` is in `filter_parameters`?
2. Why is `max_complexity` useless on our schema until we add the list multiplier?
3. Why can rack-attack not simply throttle "the login route", and what does the alias loophole look like?
4. Why do rack-attack tests need their own cache store and a teardown?
5. A teammate says "we turned introspection off, so the schema is secret and policies can wait." What is wrong?
6. Why is CORS not what protects patient data here?

**Answers**
1. `filter_parameters` is applied to **request parameters** by Rails' request logging. Active Job's log subscriber formats job arguments itself and never calls the filter. The fix is to stop logging arguments (`log_arguments = false`).
2. Our lists are plain arrays. GraphQL-Ruby multiplies by page size only for connections, so an array list counts as one field and a recursive query scores the same as a flat one (4, 6, 8, 10 in my test). The multiplier makes each trip around the `organization`/`patients` cycle cost 10 times more (22, 222, 2222).
3. All traffic is `POST /graphql`, so the path says nothing. You must read the body to find the operation. rack-attack counts HTTP requests, so `mutation { a: login(...) b: login(...) ... }` is one counted request with many password attempts. We block requests that contain more than one auth operation.
4. In the test env the cache is `:null_store`, so counters never grow and nothing is throttled. A test needs a `MemoryStore`. The setting is class-level state, so without the teardown it leaks into other tests, which could then be throttled by accident.
5. Introspection off only hides the schema map. Anyone who guesses field names can still call them (and error messages can still hint at names). Authentication, tenancy, and policies are the real access control. Hiding the schema just removes easy reconnaissance.
6. CORS is enforced by **browsers** and only controls which web pages may **read** responses. `curl`, a script, or an attacker's server ignores it. What protects data is the Bearer token check, the tenant scoping, and the policies. (CSRF is also not a concern, since we use a header token and not cookies.)

## 5. Takeaway (write your own, 2 lines)
Write what you learned in your own words in your notes, as agreed.

## 6. Known gaps to put in the README risk notes
- Reset token sits in the queue DB for up to 1 day in the finished job's arguments (6 hour expiry, single use).
- Lists are not paginated (`patients` returns every patient of the clinic).
- Raw request body size is not limited in the app.
- Throttle counters are only as good as `req.ip` (CHECK in production) and the cache store.
- The old REST `/api/v1/organizations` CRUD is still unauthenticated and bypasses **all** of this guide (plan item 4, next).

## 7. Commit plan (when you ask me to commit)
Each commit keeps the suite green. No `Co-Authored-By` line.
- `fix: stop logging job arguments and redact graphql credentials in logs`
- `test: add log hygiene tests`
- `feat: lower query depth, add list complexity limit and disable introspection in production`
- `test: add query limit tests`
- `chore: add rack-attack`, then `feat: throttle login and password reset with rack-attack`
- `test: add rate limit tests`
- `feat: add cors for the frontend` (only if you decided you need it)

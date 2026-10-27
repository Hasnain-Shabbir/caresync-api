# Audit of functionRX-api (company project) and what to learn from it

Written for you, to decide **what to learn and build next in CareSync**. Not a review for the team. Simple English, Express comparisons where useful.

## 0. Scope and honesty

- **Repo audited:** `/Users/hasnain/projects/functionRX-api` (branch state as found, 725 commits, latest 2026-10-20). There is also `functionRX-api-address`. I did **not** audit that one. Tell me if you meant it.
- **Method:** read-only. I read the Gemfile, `db/schema.rb`, models, GraphQL layer, interactors, services, jobs, config, specs, Dockerfile, buildspec, scripts. I **ran nothing**, changed nothing in that repo (its `git status` was clean), and did not open any credentials files (there are Firebase JSON key files outside the repo in `~/Downloads` and in `function-rx-app`, I left them alone). I did not copy secrets, account ids, or hostnames into this file.
- **Evidence labels:** every point names the file where I saw it. **[read]** means I saw it in code. **[not checked]** means I did not verify it (for example, protections that could exist outside the repo, like a load balancer rule).
- **Not exhaustive.** 304 GraphQL files and 99 interactors. I sampled the core flows (users, assessments, billing, auth). Version end-of-life statements are from my memory, not checked online.
- **Some findings are security issues in a live system.** You may want to raise them with your team through the normal channel. I list them in section 4.

---

## 1. Snapshot

| Item | FunctionRX | CareSync (for comparison) |
|---|---|---|
| Rails / Ruby | 7.0 / 3.2.2 [read] | 8.1 / 3.4.2 |
| Web server | Puma `~> 4.1` [read] | Puma current |
| Background jobs | **Sidekiq 7.3.7 + Redis**, `sidekiq-cron` via a rake task [read] | Solid Queue (DB-backed, no Redis) |
| Primary keys | **UUID everywhere** (`gen_random_uuid()`) [read] | bigint |
| Tables / migrations | 33 tables, 83 migrations [read] | 4 tables |
| App code | models 2.4k lines, **GraphQL 8.4k (304 files)**, **interactors 7.9k (99 files)**, services 1.3k, jobs 0.2k [read] | much smaller |
| Tests | **25 spec files, about 1.1k lines** (RSpec, FactoryBot) [read] | 167 Minitest tests |
| Auth | Devise + devise_invitable, **hand-rolled JWT**, denylist table (`jwt_blacklist`) [read] | Devise-JWT, **allowlist** |
| Authorization | hand-written `authenticate_*!` role checks [read] | Pundit |
| Audit trail | **paper_trail on all models**, `whodunnit` = current user [read] | none |
| PHI encryption | `encrypts` on client fields [read] | none |
| Integrations | Stripe (subscriptions, usage, invoices, webhooks), Twilio SMS, Expo push, SignWell (documents), Google Calendar and OAuth, S3, ActionCable chat, GraphQL subscriptions [read] | none |
| Delivery | Docker, **AWS CodeBuild, ECR, ECS** (separate app and worker services), CloudFront, Secrets Manager, RDS with SSL [read] | none yet |

Domain in one line: a clinic platform where practitioners assess clients, assign exercise **sequences**, bill clinics by **usage** through Stripe, with chat, SMS, push notifications, and signed documents.

---

## 2. What it does well (learn from these, then build them in CareSync)

| # | Pattern | Where [read] | Why it is worth learning |
|---|---|---|---|
| 1 | **Audit trail for free** with `has_paper_trail` in `ApplicationRecord`, and the GraphQL controller wraps execution in `PaperTrail.request(whodunnit: current_user.id)`. A `versions` table records every change and who did it. | `application_record.rb`, `graphql_controller.rb` | Closes CareSync's biggest HIPAA gap ("who changed this patient"). Learn the trade-offs: table growth, PHI copied into `versions`, `object_changes` JSON size. |
| 2 | **`encrypts` on PHI** (names, phone, address, date of birth, medical history). | `users/client.rb` | The real-world version of CareSync finding 5. **But see the flaw in section 3, item 4**, so we learn the correct version. |
| 3 | **UUID primary keys** with a generator default. | `config/initializers/generators.rb`, schema | Answers CareSync finding 8 (guessable ids). Learn index and ordering trade-offs. |
| 4 | **STI for roles** (`Users::Client`, `Practitioner`, `ClinicAdmin`, `SuperAdmin`, `TeamMember`). | `app/models/users/` | A real example to compare with our role enum + Pundit. Teaches STI strengths and pain (70-column `users` table). |
| 5 | **Interactor layer** (`Assessments::FetchAssessments`, `Exercises::Create`): GraphQL class stays thin, logic lives in a plain object returning success or failure. | `app/interactors/` | The pattern your team uses daily. CareSync puts logic in mutations. Learn both, decide when each fits. |
| 6 | **Filter objects** (`Filters::FilterParams`) and a pagination concern for list screens. | `services/filters`, `concerns/pagination.rb` | Real list screens (filters, search, date ranges, ordering). |
| 7 | **Stripe webhook verifies the signature** (`construct_event`). | `payments/stripe_webhook_handler.rb` | Correct first step. Missing pieces are in section 3. |
| 8 | **Usage-based billing model**: `clinic_usages` per billing cycle, unique index on clinic + cycle dates, `clinic_usage_prices` mapped to Stripe prices. | schema | A good, small, realistic data-design case (unique constraint doing real work). |
| 9 | **Real-time**: ActionCable, GraphQL subscriptions, chats and messages tables. | `graphql_boilerplate_schema.rb`, schema | CareSync has none. A whole learning area. |
| 10 | **File handling**: Active Storage to S3, `apollo_upload_server` for GraphQL multipart uploads, signed documents. | Gemfile, models | Common production need. |
| 11 | **Opaque GraphQL ids** with a type hint (`P_base64...`) via `id_from_object` / `object_from_id`. | schema file | Schema-design topic (Relay Node interface). |
| 12 | **Delivery pipeline**: separate web and worker containers, `/health` endpoint, `force_ssl`, DB SSL cert, secrets pulled from a secrets manager. | `buildspec*.yml`, `Procfile`, `routes.rb`, `config/environments` | The ops side CareSync lacks. |
| 13 | Soft-state flags (`archived`, `deleted`, `revoke_access`) and scheduled archive (`ArchiveClinicJob`). | schema, jobs | A real soft-delete example. Learn the better timestamp version (`discarded_at`). |

---

## 3. Gaps and risks (ranked)

These are things to **avoid copying**, and good learning cases. Severity is my judgment.

### High

| # | Finding | Evidence | Impact | CareSync status |
|---|---|---|---|---|
| 1 | **CORS allows every origin**: `origins "*"`, `resource "*"`, all methods. | `config/initializers/cors.rb` [read] | Any website's JavaScript can call the API from a user's browser (it still needs a token, so this is not an open door, but it is far wider than needed). | CareSync: one explicit origin, `/graphql` only (guide 09). |
| 2 | **Sidekiq dashboard is mounted in production and staging** with no authentication visible in `routes.rb` (only a cookie session store is set). | `config/routes.rb` [read]. **[not checked]** whether a gateway or network rule protects `/sidekiq`. | If reachable, anyone can see and retry or delete jobs, and job arguments can contain personal data. | n/a. Learn: protect with an auth constraint, or do not mount in production. |
| 3 | **`RAILS_MASTER_KEY` is passed as a Docker build argument and set with `ENV`** in the production image. | `Dockerfile.prod`, `buildspec*.yml` [read] | The key that decrypts all credentials is baked into the image metadata. Anyone who can pull the image can read it (`docker history`, `docker inspect`). | Learn: build secrets (`--secret`), runtime secret injection. |
| 4 | **PHI is encrypted, then copied in plain text.** `encrypts :first_name, :last_name, :phone, :address ...` but a `before_save` writes normalized **plain text** copies into `first_name_search`, `last_name_search`, `phone_search`, `address_search`, `email_search`, and these columns are indexed. | `users/client.rb`, schema [read] | The encryption protects the original columns only. The shadow columns hold the same data readable by anyone with DB access, backups, or a SQL injection. | Learn the correct pattern: blind index (HMAC of the normalized value) for exact match, deterministic `encrypts` where needed, and accept that fuzzy search on encrypted data is a design trade-off. |
| 5 | **No depth limit, no complexity limit, no rate limiting, no introspection control** in the schema or config. | grep for `max_depth`, `max_complexity`, `introspection`, `Rack::Attack` found nothing [read]. **[not checked]** whether production blocks these elsewhere. | One query can be made very expensive. No brute force protection on login or OTP (the OTP codes in `users` make this more important). | CareSync: all four (guide 09). |
| 6 | **Internal error text goes to the client.** Interactors and queries do `rescue ... StandardError => e` then return `e.message`. | `exercises/create.rb`, `queries/assessments/fetch_assessments.rb` [read] | SQL fragments, class names, and paths can leak. It also hides real bugs by turning every exception into a normal-looking error. | Learn: expected vs unexpected errors, error masking, error tracker. |
| 7 | **CI does not run tests.** The buildspec installs, migrates the staging DB, builds, pushes `:latest`, and force-deploys. | `buildspec.yml`, `buildspec-prod.yml` [read] | Nothing stops a broken or insecure change from deploying. Migrations run **before** the new code is live (old code on new schema is a classic outage). A single `:latest` tag makes rollback hard. | Learn: CI gates, versioned image tags, safe migrations (plan Track D). |
| 8 | **Old versions.** Rails 7.0, Ruby 3.2.2, Puma 4.1, `rspec-rails` 5. | Gemfile [read]. EOL dates from my memory, **[not checked online]**. | Rails 7.0 and Ruby 3.2 are, as far as I remember, out of security support, Puma 4 is far behind. No `bundler-audit` or `brakeman` in the Gemfile. | CareSync runs both tools. Learn: upgrade strategy. |

### Medium

| # | Finding | Evidence | Note |
|---|---|---|---|
| 9 | **Billing drift risk.** `UsageTracker.increment_usage` calls Stripe **inside the request** and swallows any error ("billing will be handled by webhooks and manual reconciliation"). | `services/usage_tracker.rb` [read] | A failed call means the clinic is not billed and nobody is told. Learn: do it in a background job with retries, idempotency keys, an outbox table, and a reconciliation job. |
| 10 | **Webhook error handling** rescues everything and only notifies. I did not see a de-duplication check on the Stripe event id in what I read. | `stripe_webhook_handler.rb` [read, first 80 lines] **[not checked]** the rest | Stripe retries. Without idempotency a retry can apply an event twice. |
| 11 | **Dead code in the payment path.** The handler and payment processor reference `Users::Learner`, `booking_orders`, `lesson_bookings`. No such class or table exists in this repo. | grep in `app/` and schema [read]. **[not run]** | Looks like leftovers from another product (the schema is named `GraphqlBoilerplateSchema`, and there is a `graphql_boilerplate.dump`). Those branches would raise at runtime. Worth confirming with the team. |
| 12 | **Display ids computed with a window function at query time**: `AS-00042` comes from `ROW_NUMBER() OVER (ORDER BY created_at)` over the **whole table** on every search. | `concerns/searchable.rb` [read] | Slow (full table scan per search). Wrong over time: delete one row and every later id shifts. Learn: a stored column fed by a sequence. |
| 13 | **Search is `ILIKE '%keyword%'`** across several columns with `OR`. | `searchable.rb` [read] | A leading wildcard cannot use a normal B-tree index. Learn `pg_trgm` and full-text search. |
| 14 | **Offset pagination with expensive counts**: `distinct.count(:id)` before ordering, `Kaminari.paginate_array` (loads all rows into Ruby first). | `concerns/pagination.rb`, `assessments/fetch_assessments.rb` [read] | Slow on large tables and the page can shift while the user scrolls. Learn keyset (cursor) pagination. |
| 15 | **`filter_parameters` is short**: it lacks `email`, `phone`, `date_of_birth`, and the GraphQL `query` string. | `filter_parameter_logging.rb` [read] | Same class of leak as CareSync's guide 09 step 1. |
| 16 | **Very little test coverage on the core domain.** Specs exist for users, admins, a few types. I saw **no** spec files for assessments, sequences, payments or billing (the `spec/jobs` folder is empty). | `spec/` listing [read] | The highest-risk code (money, PHI, scheduling) has no safety net. |
| 17 | **Wide `users` table (about 70 columns)** mixing identity, clinical data, OTP codes, invitation fields, and document signing. Also **no `CHECK` constraints anywhere**, `status` columns are free strings, and `bio` is a `datetime` (looks like a type mistake). | schema [read] | STI trade-off in action. Learn: when to split to profile tables, constraints, types. The `bio` type is worth confirming with the team. |
| 18 | **Authorization is repeated by hand** in each interactor with a `case current_user when Users::ClinicAdmin ...`. | `fetch_assessments.rb`, `permission_handler.rb` [read] | Easy to forget in one place. Compare with Pundit `policy_scope` (CareSync guide 07 and the comparison doc). |
| 19 | **Dataloader is enabled but unused** in `app/graphql`. N+1 is handled with `includes` in interactors. | grep [read] | Works until a nested field is added that the interactor did not include. |
| 20 | **Debug leftovers**: `p "File attached successfully"` in an interactor. | `exercises/create.rb` [read] | Small. Prints in production logs. |

### Low
- Boilerplate leftovers in names (`GraphqlBoilerplateSchema`).
- Boolean soft-delete flags instead of timestamps.
- `Procfile` runs `rails server` rather than `puma` directly (fine).

### Where CareSync is already ahead (keep these, and teach them back if useful)
Depth and complexity limits, rack-attack with the alias-batching guard, log redaction including job arguments, Pundit policies with a coverage test, errors-as-data contract, tenancy tests, password reset hardening, and 167 tests with brakeman and rubocop clean. FunctionRX is ahead on **breadth**: billing, real-time, files, audit, encryption, delivery.

---

## 4. Things you may want to raise with your team (your call)

In order of how quickly they could matter, all **[read]**, none verified against the live system:
1. `/sidekiq` mounted in production without visible auth (item 2).
2. `RAILS_MASTER_KEY` baked into the image (item 3).
3. Plain-text search copies of encrypted PHI (item 4).
4. `origins "*"` CORS (item 1).
5. No rate limiting on login or OTP flows (item 5).
6. CI deploys without running tests (item 7).

Before raising any of them, **check the live setup yourself** (for example, is `/sidekiq` reachable from outside?). I could not.

---

## 5. Learning plan from this audit (merges with `learning-plan-production-rails.md`)

The earlier plan covered database design, ActiveRecord, queries, and production basics. This audit adds **what your real project actually uses**. Tracks continue the earlier lettering (A to I).

### Track J. Integrations and async reliability (priority: MUST, your team lives here)
Stripe subscriptions and **usage metering**, webhooks done right (signature, **idempotency by event id**, retries, ordering), background jobs with retries and dead-letter handling, **outbox pattern**, reconciliation jobs, idempotency keys on outgoing calls, Twilio and push notification logs.
Build in CareSync: a small `clinic_usages` table plus a `UsageEvent` outbox, a job that reports to a fake Stripe client, a webhook endpoint with a de-dup table, and tests that replay the same event twice.
Done when: killing the process mid-call never loses or double-counts a usage event.

### Track K. PHI protection done correctly (priority: MUST, for the HIPAA story)
`encrypts` deterministic vs non-deterministic, **blind indexes** (HMAC) for search, what cannot be searched, key rotation, **paper_trail** or a custom audit table (what to store, what to redact in `versions`), field-level access logging, soft delete with retention.
Build in CareSync: encrypt `date_of_birth` and names, add a blind index for exact last-name search, add auditing with `whodunnit`, and a test that fails if plain text appears in the DB or in `versions`.
Done when: a DB dump alone does not reveal a patient name, and you can answer "who changed this record, when".
(This replaces the earlier "Guide 16" and makes it concrete.)

### Track L. Domain code structure (priority: SHOULD)
**Interactors vs service objects vs fat mutations**, where authorization lives, `Result` objects, thin GraphQL classes, error handling that does not swallow bugs. **STI vs delegated types vs role enum**, with the 70-column table as the case study. Authorization: Pundit vs hand-rolled (you already have the comparison doc).
Build in CareSync: move one mutation (for example `createPatient`) into an interactor, compare the diff and tests, decide.
Done when: you can argue for or against interactors for a given feature, and name what STI costs.

### Track M. Real-time and files (priority: SHOULD)
ActionCable, **GraphQL subscriptions**, chat data model, presence, scaling subscriptions (Redis or Solid Cable), Active Storage with S3, direct uploads, GraphQL multipart uploads, virus scanning and PHI in file names.
Build in CareSync: a simple `messages` subscription and one authorized file upload.
Done when: a user only receives events for their own clinic and uploads are scoped and authorized.

### Track N. Delivery on AWS (priority: SHOULD, matches your company stack)
Docker multi-stage builds without secrets in layers, **CI that runs tests before deploying**, versioned image tags and rollback, running migrations safely (expand/contract, before vs after deploy), ECS app and worker services, health checks, secrets from a secrets manager at runtime, RDS SSL, zero-downtime deploys, CloudWatch logs and alarms, backups and restore drills. (Kamal from the earlier plan is an alternative to learn the same ideas on a plain VM.)
Build in CareSync: a Dockerfile, a CI workflow (tests, brakeman, bundler-audit, rubocop), a staging deploy.
Done when: a red test blocks a deploy and you can roll back by tag.

### Track O. Upgrades and maintenance (priority: LATER but valuable)
Rails and Ruby upgrade paths (7.0 to 8.x), `next_rails` and deprecation warnings, `bundler-audit`, Dependabot, pinning and testing gems, upgrading Sidekiq and Puma. A good skill for a team on Rails 7.0.
Exercise: take a throwaway copy of a small Rails 7.0 app and upgrade it step by step.

### Sidekiq vs Solid Queue (a decision, not a track)
Your company uses **Sidekiq + Redis**, CareSync uses **Solid Queue**. Learn Sidekiq basics too (retries, queues, `sidekiq-cron`, Web UI auth, Redis persistence) because that is what you will meet at work. Add a short comparison doc. You do not need to switch CareSync.

---

## 6. Company feature to CareSync exercise (so each lesson is concrete)

| Company feature | CareSync exercise | Teaches |
|---|---|---|
| paper_trail + whodunnit | Audit patients and users | audit design, Track K |
| `encrypts` + search columns | Encrypt DOB and name, blind index | Track K |
| UUID keys | Migrate `patients` to UUID (or add a public UUID) | index and ordering trade-offs |
| `clinic_usages` + Stripe | Usage metering with outbox and fake Stripe | Track J |
| webhooks | Idempotent webhook endpoint with replay test | Track J |
| `ROW_NUMBER` display ids | Add `patients.display_id` from a sequence | window functions vs sequences, Track C |
| Searchable `ILIKE` | Patient search with `pg_trgm`, compare plans | Track C |
| Kaminari offset pagination | Keyset cursor connection for `patients` | Track C and G |
| ActionCable chat | Messages subscription scoped by clinic | Track M |
| interactors | Move `createPatient` into an interactor | Track L |
| buildspec / ECS | CI with tests gate, Dockerfile, staging deploy | Track N |
| sidekiq-cron | Same recurring job in Solid Queue `recurring.yml` | job scheduling both ways |
| `virtual_therapy_appointments` | `appointments` with an exclusion constraint against double booking | Track A and B |

---

## 7. Suggested order (merged with the earlier plan)

Today is 2026-10-22, the submission project is due 2026-10-30.

1. **Now:** finish CareSync's open items (remove REST, guide 07 sections 4.2 and 4.3, README).
2. **Before the submission project:** Track A basics, Track C items 1 to 4 (from the earlier plan). Add **Track K** only if the submission handles personal data.
3. **After submission, in this order:** K (PHI protection), J (integrations and idempotency), C and G (cursor pagination), L (structure), N (CI and delivery), M (real-time and files), then B, D, E from the earlier plan, then O.

**Why this order:** K and J are what your team's product depends on and where the audit found the sharpest problems. N makes everything else safe to ship.

## 8. How to use this audit
Read section 3 and try to explain, in your own words, **why** three items are problems (suggest 4, 9, and 12). That is the check that the lesson stuck. Then pick tracks and I will write the guides in the usual format, one at a time, you type the code.

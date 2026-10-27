# SaaS template backend: standards, folder structure, Claude rules and skills (for your review)

One document to read, decide on, and then turn into files in the new repo. Written for you. Parts are meant to be shown to your lead. Simple English, Express comparisons where useful.

## 0. How to read this, and honesty notes

**What I studied (read-only, nothing run, nothing changed in any company repo):**
- `bliv-platform-backend`: your main reference. 4,482 commits, 2025-01-11 to 2026-09-09, mostly Moiz Ali and Minal Shahzad. Rails 7.2, Ruby 3.4.1. I read the README, Gemfile, schema, app tree, GraphQL schema and controller, base classes, authorization and authentication concerns, one mutation, query, interactor, form, service, job, the webhooks controller, models (`Patient`, `User`, `ApiToken`), and the config (CORS, filter parameters, initializers, Procfile, docker-compose).
- `functionRX-api` and `AKU-app`: earlier audits (see [audit-functionrx-api.md](audit-functionrx-api.md)) plus targeted checks for this document.
- `saas-setup/.claude`: the frontend's rules, skills, `skills-lock.json` and `settings.json`, so the backend follows the same convention.
- External skills: the repositories' public GitHub pages (via web fetch), not the full skill files.

**What I did not do:**
- I did not run any company code, and I did not test any live system.
- I did not read all 188 interactors, 97 services, and 291 GraphQL files of bliv. I read representative files in each layer. Where I generalize, I say so.
- I did not read the actual `SKILL.md` text of the external skills. I read each repo's page. **Read a skill's file before installing it** (section 7).
- Rules in section 6 are **proposals** that come from patterns I saw, general practice, and the standards named in section 4. I did not open OWASP, NIST, or the Rails guides in this session, so where I cite them it is from my own knowledge. **Treat the cited standards as pointers to check, not as verified quotes.**

**One thing you should know first:** section 2 reports security problems in company code, including one that looks serious. Please read it before anything else.

---

## 1. Summary (the decisions you need to make)

1. **Read section 2 and decide how to raise it with the team.** It affects whether bliv is a safe model to copy.
2. **bliv is a good reference for structure, not for quality practices.** It has a clear domain-per-layer layout and several strong patterns, but this repository has **no tests, no linter config, no CI, no docs** (and never had any, in its git history). It cannot be your reference for those. Section 3 splits "keep" from "improve" from "avoid".
3. **Proposed backend architecture** (section 5): thin GraphQL layer, then application services returning a Result, then models, query objects, and policies. Decide: plain service objects (my recommendation) or the `interactor` gem (what all three company projects use).
4. **Proposed Claude setup** (section 6): 16 rule files, a `settings.json` with a secrets deny list, `CLAUDE.md`, and 7 project skills that we write ourselves.
5. **External skills** (section 7): the Rails plus GraphQL ecosystem is thin. I recommend vendoring only a few vetted skills, pinned in a lock file like the frontend does, and putting most effort into our own project skills.
6. **Nothing is created yet.** The backend repo does not exist. After you approve, the files go into the new repo.

---

## 2. Urgent: security findings in the company repos

**How I verified, and what that means.** All of these come from **reading code**. I did not test any live system, and you should not either. The one gem-behavior claim I ran in isolation (no app, no network): with the `jwt` gem, `JWT.decode(token, key, false)` returns the payload for a token signed with a **different key** that is also **already expired**, while `JWT.decode(token, key, true, algorithm: 'HS256')` raises `JWT::VerificationError`.

### 2.1 bliv: request authentication does not verify the token signature (looks critical)
- `app/controllers/concerns/authenticable.rb` line 15: `JWT.decode(auth_token, secret_key, false)`. The third argument is `verify`, so signature and expiry are **not checked**.
- This concern is included by `ApplicationController`, and `GraphqlController` builds `current_user` and `current_patient` from it (`User.find_by(id: payload['sub'])`).
- Tokens are issued in `app/interactors/users/generate_token.rb` with `JWT.encode(payload, SECRET_KEY)` and a `sub` and `exp`. That is the only `JWT.decode` or `encode` in the app.
- The GraphQL `ready?` check (`Authorization` concern) then checks the `api_tokens` row's expiry **only if one is found** (`api_token && api_token.expiry <= now`). A token with no row gives `nil`, which counts as "not expired".
- Reading this together, a token that was never issued by the server, carrying a valid user id in `sub`, would appear to authenticate. **I have not tested it.** The impact depends on how hard user ids (UUIDs) are to learn. This is a healthcare app with patient data.
- **What to do:** do not try it on a live system. Tell the engineers and your lead what you read and where (file and line). They can confirm in a local or staging environment and fix it. The fix is one argument, but the team should also rotate secrets if they conclude a forged token was possible.

### 2.2 bliv: tokens stored in plain text, no index
`api_tokens.token` is a `text` column holding the full JWT, with no digest, no unique index, no index at all (only `user_id`, `patient_id`). A database leak exposes every live token, and `where(token: ...)` scans the table.

### 2.3 bliv: "blind index" uses unkeyed SHA-1
`Patient` encrypts email, names, phone, date of birth, and addresses with `encrypts` (good), then stores search digests with `Digest::SHA1.hexdigest(value.downcase)` (`patient.rb` lines 72, 78, 205). Unkeyed SHA-1 of a name, phone number, or state can be reversed by a dictionary attack by anyone with the database, which defeats much of the encryption. The idea is right, the primitive is wrong (use HMAC-SHA256 with a key stored outside the database, or `encrypts ..., deterministic: true` for exact match).

### 2.4 bliv and functionRX-api: CORS allows every origin
`config/initializers/cors.rb` in both: `origins "*"`, `resource "*"`, all methods. (A bearer token is still needed, so this is wider than needed, not an open door.)

### 2.5 bliv: webhook endpoints are not consistent
In `webhooks_controller.rb`: DoseSpot (`VerifySecret`), Stripe (handler) and Authorize.net (checks `X-Anet-Signature`) verify something. The PerfectRx and Scripts actions, in what I read, create a log row and enqueue a job **with no verification step visible**. **[Not verified]**: a check could exist elsewhere (a `before_action` in a part of the file I did not read, a gateway rule, or an IP allow list).

### 2.6 bliv: exception notifier receives GraphQL variables
`graphql_controller.rb` passes `query` and `variables` to `ExceptionNotificationService.notify_graphql_exception`. In a healthcare app, variables can carry personal data or passwords. **[Not verified]** what the service redacts. I did not read it.

### 2.7 Smaller items (bliv)
- **Individual email addresses are hard-coded** in code (a constant in `User`, a default recipient in a job). Configuration belongs in credentials or environment variables.
- **No query depth or complexity limits** (only `max_query_string_tokens`). Same as functionRX.
- **Permissions are about 25 boolean `can_*` columns** on `users`, set by role in a `before_save`. Hard to evolve and to audit.
- **Zero `CHECK` constraints** in the schema (53 tables, 62 foreign keys, 143 indexes), enums are integers.
- **Two pagination libraries plus a GraphQL pagination gem** in the Gemfile (`pagy`, `kaminari-activerecord`, `graphql-pagination`).
- **`rescue => error; context.fail!(error: error.message)`** is the common interactor pattern (also in functionRX). It hides bugs and can send internal text to the client. (bliv's `ErrorHumanizer` module exists to improve this, but the pattern remains in files I read.)

### 2.8 Earlier findings
FunctionRX items (plain-text search copies of encrypted PHI, Sidekiq dashboard without visible auth, master key as a build argument, no CI test gate) are in [audit-functionrx-api.md](audit-functionrx-api.md). AKU's request path **verifies** the token and checks a denylist (the unverified decoder there is in a concern that nothing includes).

### 2.9 How to raise it (suggestion)
Short, factual, file-and-line, no drama, no live testing, and recommend a verification in a non-production environment. Something like: "While studying bliv for our template, I read `Authenticable#decoded_token` and noticed `JWT.decode(..., false)` on the request path (authenticable.rb:15). Could someone confirm in staging whether tokens are signature-checked elsewhere?" Your lead decides the channel.

---

## 3. What the three repos teach (keep, improve, avoid)

### 3.1 bliv structure (the senior engineers' work), as I read it

| Area | What I saw | Verdict |
|---|---|---|
| **Domain per layer** | The same domain name repeats in each layer: `graphql/mutations/patients/`, `graphql/queries/patients/`, `interactors/patients/`, `jobs/patients/`, `services/<provider>/` | **Keep.** Easy to find everything for a feature |
| **Thin GraphQL classes** | Mutations and queries call one interactor and map `success?` to a result or `execution_error`. `BaseMutation`, `BaseQuery`, an `ExecutionErrorResponder` concern | **Keep the thinness.** Improve the error mapping (codes, no raw messages) |
| **Interactors** (188 files) with a `BaseInteractor` | One use case per class, `Domain::Verb` names (`Patients::All`, `Patients::Create`), shared helpers in `interactors/helpers` | **Keep the one-use-case-per-class idea.** Improve the error handling (see 2.7) |
| **Services** (97 files) | One folder per external provider (Stripe, Twilio, DoseSpot, ...), separate small classes such as `Twilio::SignatureValidator` | **Keep** (provider folders, validators as their own classes) |
| **Inbound webhooks as an inbox** | `ThirdPartyApiLog` row stores the raw payload, then a job processes it by log id | **Keep.** Strong pattern. Add a unique event id for idempotency |
| **`ApplicationRecord` has `has_paper_trail`** and the controller sets `whodunnit`, including for impersonation | audit trail for every model | **Keep.** Decide what is never stored (secrets, PHI) |
| **State machines with `aasm`** in model concerns (intake form, medication flow) | explicit workflow states | **Keep** for real workflows. Not for simple flags |
| **Namespaced jobs and named queues** (`integrations`, `default`, `mailers`, `imports`) | `Patients::ElationImportAuditJob`, `queue_as :imports` | **Keep** |
| **GraphQL base types** and custom scalars (timezone-aware date and time), `Types::Enums`, a `node_type` | consistent schema vocabulary | **Keep** |
| **Docs inside code** (the `ErrorHumanizer` header explains usage, comments say why) | helpful | **Keep the habit.** Add real docs (README, ADRs) |
| **`docker-compose.yml`** with Postgres 16, Redis 7 and health checks, plus a `Procfile` with a release step | easy local setup | **Keep** |
| **Form objects** in `app/forms` | These map our data to **outbound** third-party payloads (PerfectRx, Scripts). They are not input forms | **Rename** to avoid confusion (`app/payloads` or `app/services/<provider>/payloads`) |
| **Model concerns by model** (`patient_concerns/`, `user_concerns/`) | split large models | **Keep, with limits** (section 6, rule 8) |
| **Permissions as boolean columns** | explicit, but rigid | **Avoid.** Use policy objects (and a permission matrix test) |
| **Auth** | see 2.1 and 2.2 | **Avoid. Do not copy.** |
| **Tests, lint, CI, README** | none in the repo, never in history | **Add from day one** in the template |
| **Hard-coded config and personal emails** | see 2.7 | **Avoid** |
| **Search digests** | see 2.3 | **Fix the primitive** |

### 3.2 Side by side (all three, plus CareSync)

| | bliv | functionRX-api | AKU-app | CareSync |
|---|---|---|---|---|
| Rails / Ruby | 7.2 / 3.4.1 | 7.0 / 3.2.2 | 7.0 | 8.1 / 3.4.2 |
| Business logic layer | interactors + services | interactors + services | interactors | in mutations |
| Authorization | boolean permission columns + role enum | hand-written role checks | role checks | Pundit |
| Audit | paper_trail (all models) | paper_trail (all models) | none seen | none |
| Tests in repo | **none** | 25 spec files | specs exist (not counted) | 167 tests |
| Lint and CI | none | rubocop only (no CI gate) | rubocop | rubocop, brakeman |
| Ids | UUID | UUID | UUID | bigint |
| Jobs | Sidekiq | Sidekiq | Sidekiq | Solid Queue |
| Depth and complexity limits | none | none | not checked | yes |
| Rate limiting | none seen | none | none seen | rack-attack |

### 3.3 What this means for the template
The company's **structure** is a good starting vocabulary (domain per layer, thin GraphQL, one class per use case, provider folders, inbox for webhooks). The company's **quality bar** (tests, CI, security review, constraints) is something the template has to add, because none of the three repos can show it. That is a fair thing to tell your lead: the template's value is the baseline these projects lack.

---

## 4. Principles behind the proposed rules

Rules should be few, checkable, and each should come from a real failure or a stated standard. Priority order when rules conflict:
1. **Security and privacy** (tokens, secrets, PHI, authorization).
2. **Data integrity** (constraints in the database, transactions, idempotency).
3. **Operability** (logs, errors, deploy, rollback).
4. **Simplicity** (fewest moving parts that meet the need).
5. **Team fit** (what the team can maintain).

Standards to check against (I have **not opened** them in this session): OWASP Cheat Sheets for authentication, session management, forgot password, and GraphQL; the OWASP Top 10; the Rails Security Guide; 12-factor app; NIST SP 800-63B for authenticator lifetimes; PostgreSQL docs for constraints and indexing; HIPAA Security Rule safeguards if a product handles PHI.

---

## 5. Proposed architecture and folder structure

### 5.1 Layers (who may call whom)

```
GraphQL (types, mutations, queries)      thin: parse input, authenticate, call a service, shape the output
        |
Application services (one use case each)  business rules, transactions, calls to integrations, returns a Result
        |
Models + query objects + policies         data rules and constraints | read/filter/search logic | who may do what
        |
PostgreSQL (constraints are the last line of defence)
Jobs and mailers call services; webhooks enqueue jobs. Nothing calls "up" the diagram.
```

**Decision L1: plain service objects or the `interactor` gem?**

| | Plain service objects (`.call`, returns a `Result`) | `interactor` gem (what the company uses) |
|---|---|---|
| Dependencies | none | one small gem (I have **not checked** how actively it is maintained) |
| Familiarity | new to the team (small step) | all three company repos |
| Failure handling | explicit `Result.failure(code:)` or domain exceptions | `context.fail!` (nothing forces a code, and in practice `rescue => e` plus `e.message` appeared) |
| Composition | call another service | `organize` chains |
| Tests | plain Ruby | plain Ruby |

My recommendation: **plain services with an explicit Result and typed domain errors**, because the failure mode we saw in practice (everything rescued and its message returned) is easier to forbid in a rule when failures are values with codes. If the lead prefers team familiarity, use `interactor` with the same rules (no rescue-all, failures carry a code). Either way the layers do not change.

### 5.2 Folder structure (proposed)

```
app/
  graphql/
    schema.rb                       limits, introspection, error mapping
    errors/                         error codes and mapping to extensions.code
    types/<domain>/                 one folder per domain (+ base_*.rb, scalars/, enums/)
    mutations/<domain>/<verb_noun>.rb     BaseMutation (Relay classic), inputs
    queries/<domain>/<verb_noun>.rb       BaseQuery
    concerns/                       authentication, authorization, pagination helpers
  services/<domain>/<verb_noun>.rb  use cases, return a Result  (e.g. Users::Register)
  integrations/<provider>/          external clients, signature validators, payload mappers
  queries/<domain>/                 query objects (filtering, search, pagination)
  policies/                         one policy per resource, default deny
  models/                           data rules only (+ concerns/, few and small)
  jobs/<domain>/                    thin: load by id, call a service
  mailers/
  validators/
config/
  initializers/                     one file per concern (cors, rack_attack, flipper, sentry)
db/migrate/                         reviewed by strong_migrations
docs/
  architecture.md                   this layering, one page
  decisions/                        one file per decision (ADR-lite)
  runbook.md                        deploy, rollback, rotate secrets, on-call basics
spec/                               mirrors app/ (see rule 13)
.claude/                            rules/, skills/, settings.json
.github/workflows/ci.yml            tests, rubocop, brakeman, bundler-audit (a hard gate)
CLAUDE.md, AGENTS.md                short index pointing at the rules
bin/setup                           one command to a running dev environment
docker-compose.yml                  Postgres and Redis with health checks
```

Notes on what changed from bliv: `forms` becomes `integrations/<provider>/payloads`, "services" for external providers move to `integrations/` so `services/` always means "our use cases", and `docs/`, `spec/`, `.github/` exist from day one.

### 5.3 Naming conventions
- **GraphQL operations:** `<Verb><Noun>` in PascalCase. These names are part of the contract with the frontend (it keeps lists of pre-auth operation names and e2e mocks keyed by name).
- **Services:** `Domain::VerbNoun` (`Users::Register`, `Invitations::Create`), one public method `call`.
- **Jobs:** `Domain::VerbNounJob`. Arguments are ids only.
- **Policies:** `<Model>Policy`. **Query objects:** `Domain::<Thing>Query` (`Users::ListQuery`).
- **Files and classes** mirror each other (Zeitwerk). Specs mirror `app/` paths.
- **Commit messages:** `type(scope): message`, lowercase, imperative, no trailing period (copy the frontend's `commit-message.md`). No AI attribution trailers.

---

## 6. Proposed Claude rules (draft text to review)

How the pieces fit (copied from the frontend's approach):

| Piece | What it is | Loads |
|---|---|---|
| `CLAUDE.md` | a few lines: `@AGENTS.md` and "rules live in `.claude/rules`" | every session |
| `AGENTS.md` | short project overview and how to run checks | every session |
| `.claude/rules/*.md` | one concern per file. A `paths:` header makes a rule load only when matching files are touched | always, or by path |
| `.claude/skills/<name>/SKILL.md` | task playbooks ("add a GraphQL operation") | on demand, when the task matches |
| `.claude/settings.json` | permissions (deny secrets, allow safe commands) | every session |
| `.cursor/rules/*.mdc` | copy for Cursor users (the frontend keeps both in sync) | optional |

**Proposed rule files.** `always` means no `paths:` header. Text below is draft wording, short on purpose.

**1. `no-assumptions.md` (always)**
- Never assume business rules, scope, roles, or data meaning. If ambiguous, ask before writing code.
- If two approaches are valid, show both and ask.
- Never decide anything that changes business logic, permissions, or data retention without confirmation.
- (Adapted from the frontend's rule of the same name.)

**2. `no-env-access.md` (always)**
- Never read, print, or summarize `.env*`, `config/credentials*`, `config/master.key`, `*.pem`, `*.key`, cloud secret stores, or anything named like a secret. Allowed: `.env.example`.
- If you need a value, ask the user to paste only that value, redacted.
- (Adapted from the frontend's `no-env-access.md`. The backend adds `config/credentials/*.key` and `master.key`.)

**3. `architecture-layers.md` (always)**
- GraphQL classes only parse input, authenticate, authorize, call one service, and shape output. No business logic, no queries beyond a lookup, no external calls.
- Services own the use case and the transaction. They return a `Result` (success value or failure with a `code`). They do not render GraphQL errors.
- Models hold data rules (validations, associations, simple scopes). They do not call external services or send email from callbacks.
- Jobs load by id and call a service. Webhooks store the payload and enqueue a job.
- Nothing in a lower layer calls a higher one.

**4. `folder-structure-and-naming.md` (always)**
- Use the tree in `docs/architecture.md`. Put code where its domain lives (same domain name in every layer).
- `<Verb><Noun>` GraphQL operation names, `Domain::VerbNoun` services, `...Job`, `...Policy`, `...Query`.
- Do not create `app/helpers`, `app/lib`, or catch-all "Utils" or "Helpers" modules. Name things for what they do.

**5. `graphql-operations.md` (`paths: app/graphql/**`)**
- Mutations extend `BaseMutation` (Relay classic). Name operations `<Verb><Noun>`. Do not rename an operation without updating the frontend (it relies on names).
- **Default deny:** authentication is required unless the operation is on the explicit public list, which is short and tested.
- Every operation calls a policy. A new operation without a permission test fails the coverage test.
- Errors: use the error taxonomy in `app/graphql/errors`. Always set `extensions.code`. **Never return `exception.message` to the client.** Unknown errors become `INTERNAL_SERVER_ERROR` plus an error-tracker event.
- Lists: offset pagination `{count, nextPage, prevPage, totalPages, allData}` for the existing contract. New lists use cursors unless the UI needs page numbers. Every list has a maximum page size.
- Avoid N+1: use the dataloader or `includes` in the query object, and keep Bullet in test. Add a complexity multiplier to every list field.
- After any API change, dump `schema.graphql` and commit it.

**6. `authentication-and-sessions.md` (`paths: app/**/auth*, app/models/session*, app/graphql/**/auth*`) (security critical)**
- **Never** call `JWT.decode` with verification off. Never trust a token's payload without verifying the signature and expiry.
- Prefer opaque random session tokens. Store **only a digest** (SHA-256). Look up by the digest. Never store a raw token.
- Sessions have an absolute expiry and an idle timeout. Password change, archive, and access revoke delete the user's sessions.
- Codes (OTP): store an HMAC of the code, never the code. Expire in 10 minutes or less, limit attempts (5), one live code per user and purpose, constant-time compare, resend cooldown.
- Login and reset responses must not reveal whether an email exists. Same message, same status, similar timing.
- Passwords: `has_secure_password` (bcrypt). Keep a password strength rule in one place.
- Every change in this area needs a security review (skill `security-review-backend`) and negative tests (forged token, expired token, replayed code, wrong purpose).

**7. `authorization.md` (`paths: app/policies/**, app/graphql/**`)**
- Policy objects, **default deny**. Scope lists through the policy scope. Tenant scoping starts from the current organization, never from a global `Model.find`.
- Cross-tenant ids return the same `NOT_FOUND` as a missing record.
- Field-level rules (a field hidden for a role) live in the type with a policy check, with a test.
- Keep a permission-matrix test (role by operation) and a coverage test that fails when an operation has no permission test.

**8. `models.md` (`paths: app/models/**`)**
- Validations are not constraints. Every rule that matters also exists in the database (`NOT NULL`, `UNIQUE`, `CHECK`, foreign key).
- Enums are **strings with a `CHECK`**, not integers (integers cannot be safely reordered or reused).
- Callbacks: only for data shaping of the same record. No external calls, no email, no job enqueueing except `after_commit` for a job that loads by id.
- Concerns: small, named for a behavior, one level deep. A model over about 200 lines is a design smell, extract a service or query object.
- Use `normalizes` for email and similar. Use timestamps (`archived_at`) instead of booleans for state that has a time.

**9. `database-and-migrations.md` (`paths: db/**, app/models/**`)**
- One change per migration. Reversible. Reviewed by `strong_migrations` (do not disable its checks without a comment explaining why).
- Foreign keys always have an explicit `ON DELETE` and an index. Unique indexes express business rules.
- Add indexes `CONCURRENTLY` on existing tables. Add foreign keys and `CHECK` constraints `NOT VALID`, then validate in a separate step. Backfill data in a job or a separate migration, in batches.
- Types: money as integer cents plus currency, time as `timestamptz`, no `float` for money, `citext` for emails.
- Every tenant table has the organization column once multi-tenancy exists. Children use composite foreign keys so a cross-tenant link is impossible.
- Never edit a migration that has shipped. Add a new one.

**10. `services-and-jobs.md` (`paths: app/services/**, app/jobs/**`)**
- A service is one use case. It returns a `Result`. It rescues only errors it can handle, and never `StandardError` to return its message.
- Jobs: arguments are ids (no secrets, no personal data), idempotent, with explicit `retry_on` and `discard_on`. Name the queue. Sensitive jobs disable argument logging.
- Anything that sends an email, SMS, or calls a provider runs in a job, not in the request.
- Money, billing, and provider calls use an idempotency key and are reconciled by a job.

**11. `integrations-and-webhooks.md` (`paths: app/integrations/**, app/controllers/webhooks*`)**
- **Every webhook verifies its signature or shared secret, with a constant-time compare, before anything else.** An endpoint without verification is a bug.
- Store the raw payload (the inbox), with a **unique provider event id** so a replay is harmless, then process in a job. Return 2xx quickly.
- Set timeouts on every outbound call. Never log full payloads that contain personal data.
- One folder per provider. Signature validators and payload mappers are their own small classes.

**12. `security-and-privacy.md` (always)**
- No secrets, tokens, codes, passwords, or personal data in logs, exception notifiers, job arguments, or commit messages. `filter_parameters` covers request params **and** the GraphQL `query` text (inline values).
- CORS: one explicit origin from configuration. **Never `origins "*"`.**
- Sensitive fields: `encrypts`. For exact-match search use `deterministic: true` or an **HMAC (keyed)** blind index. **Never an unkeyed hash (MD5, SHA-1, SHA-256).**
- Secrets live in credentials or environment variables. Never in code, Docker build arguments, or `ENV` lines in an image.
- Production: introspection off, depth and complexity limits, rate limiting on anonymous operations, `force_ssl`.
- No hard-coded emails, ids, or hostnames in code.

**13. `testing.md` (`paths: spec/**`)**
- RSpec. `spec/` mirrors `app/`. Test through the layer's public face: request specs for GraphQL (`POST /graphql`), unit specs for services, policy specs, model specs for constraints.
- Every operation has: a success case, a validation failure, an unauthenticated case, a forbidden case, and (once tenancy exists) a cross-tenant case.
- Security paths have **negative tests** (forged token, expired token, replayed code, wrong purpose, enumeration).
- No real network (WebMock). No sleeping. Use time travel.
- Keep the coverage tests (operations vs permission tests, list fields vs complexity).

**14. `errors-and-logging.md` (always)**
- Errors carry a stable `extensions.code`. The message is safe for end users. Internal detail goes to the log and the error tracker only.
- Log at `info` in production. Structured, with a request id. No payload dumps.
- No debug prints (`p`, `puts`, `binding.pry`) in committed code.

**15. `commit-message.md` (always)**
- `type(scope): message`. Types: `feat`, `fix`, `chore`, `refactor`, `docs`, `style`, `test`. Lowercase, imperative, no period.
- Never add `Co-Authored-By`, "Generated with Claude Code" or any AI attribution.
- (Copied from the frontend's rule so both repos agree.)

**16. `working-agreement.md` (always, optional)**
- Before a task of 3 or more steps, make a todo list.
- After a task, ask follow-up questions: edge cases, related places to apply it.
- Run `bundle exec rspec`, `rubocop`, `brakeman` before saying a task is done.
- (The frontend has `always-make-todo.md` and `ask-followup-questions.md`. Merge them if you want the same behavior in both.)

### 6.1 Proposed `.claude/settings.json` (shape only)
- **deny:** reads of `.env*`, `config/credentials/*`, `config/master.key`, `*.pem`, `*.key`, shell commands that print environment or secrets (the frontend's list is a good base).
- **allow (safe, read-only or local):** `bundle exec rspec`, `bundle exec rubocop`, `bin/brakeman`, `bundle exec bundle-audit`, `bin/rails routes`, `git status/diff/log`.
- **ask:** `db:migrate`, `db:drop`, anything touching production.
- **Hooks (optional, later):** run `rubocop` on edited Ruby files; run the related spec after an edit. Add only after the basics work.

---

## 7. Skills

### 7.1 External skills I found (verified at the repo-page level only)

Provenance checked by fetching each repo's GitHub page. I did **not** read the skill files themselves. Star counts are from the pages at the time of fetching.

| Skill source | What it is | Evidence | GraphQL? | Fit | Recommendation |
|---|---|---|---|---|---|
| [apollographql/skills](https://github.com/apollographql/skills) `graphql-schema` | GraphQL schema design: types, naming, pagination, errors, security (depth, complexity, authorization) | MIT, 118 stars, semver releases, **already used by your frontend** (it is in `skills-lock.json`) | **Yes, language-agnostic** | Good for schema design rules. The server skills (`apollo-server`, federation) are JavaScript, not for us | **Vendor `graphql-schema`** (and maybe `graphql-operations`). Same source as the frontend, so both sides share vocabulary |
| [wshobson/agents](https://github.com/wshobson/agents), PostgreSQL table design (one listing shows `plugins/database-design/skills/postgresql`, named `postgresql-table-design` elsewhere) | PostgreSQL schema, types, indexing, constraints, performance | MIT, 41.5k stars for the repo. Third-party scores are mixed (about 66 to 75 percent on one registry). **The repo page I fetched did not list this plugin**, the evidence comes from registry listings | No | Good fit for database design rules, not Rails-specific | **Candidate.** Open the actual `SKILL.md` first and confirm the path |
| [thibautbaissac/rails_ai_agents](https://github.com/thibautbaissac/rails_ai_agents) | A full `.claude/` for Rails: 19 agents, 18 skills, 14 rules, 5 hooks. Layered style: service objects with a Result, query objects, Pundit policies. RSpec by default. Skills include `security-audit`, `postgres-patterns`, `authentication-flow`, `caching-strategies` | MIT, 669 stars, 90 commits | **No GraphQL** (REST-oriented) | Its **rules files** (models, controllers, services, queries, policies, jobs, migrations, testing, anti-patterns) are a good template for ours. Its Solid Queue skill does not match a Sidekiq choice | **Use as a reference** for rule structure. Do not copy wholesale (it targets REST and server-rendered Rails) |
| [igmarin/rails-agent-skills](https://github.com/igmarin/rails-agent-skills) | 28 Rails skills plus 9 workflow templates, including `implement-graphql`, `review-migration`, `implement-background-job`, authorization, security, performance | MIT, only 27 stars, 324 commits. Recency not shown on the page | **Yes** (graphql-ruby) | The only Rails plus graphql-ruby skill I found, but low adoption | **Read it, borrow ideas, do not depend on it.** Verify quality before use |
| [thoughtbot/rails-audit-thoughtbot](https://github.com/thoughtbot/rails-audit-thoughtbot) | Rails code audit: testing, security, models, controllers, design, severity levels | From a reputable consultancy. The post itself calls it "experimental" and "a starting point". RSpec-oriented | No | Useful as a periodic **review** tool | **Optional.** Try on the template once, as a second opinion |
| Others seen in search results (not opened): `sergiodxa/agent-skills` Rails best practices, `kavin-kannan/rails-best-practices-skill`, `secondsky/claude-skills` GraphQL | community skills | unknown provenance | | | **Skip** unless someone vouches for them |

**What I can honestly say:** the ecosystem for **Rails plus graphql-ruby** skills is thin and young. Nothing I found is an authoritative standard. The best use of external skills is as raw material and reference. The skills that will actually protect the project are the ones **we write from our own decisions** (7.2).

**Supply chain caution.** A skill is text that instructs an AI with your permissions. Before vendoring any skill: read the whole `SKILL.md` and referenced files, check the repo owner, pin it in a lock file (the frontend already does this with `skills-lock.json`: source, path, hash), and re-review on update.

### 7.2 Project skills we should write ourselves (from our decisions and your CareSync guides)

| Skill | Purpose | Built from |
|---|---|---|
| `graphql-operation` | Add a query or mutation: files, naming contract, args, policy, error codes, specs, schema dump | `guide-adding-a-crud-resource.md` + rule 5 |
| `domain-feature-slice` | The vertical slice checklist: migration, model, policy, service, GraphQL, specs, docs | the same guide + the playbook |
| `db-migration-review` (**review-only**) | Check a migration for locks, constraints, indexes, reversibility, backfill | rule 9, `strong_migrations` ideas |
| `security-review-backend` (**review-only**) | Check auth, sessions, OTP, logs, CORS, webhooks, secrets, PHI against rules 6, 11, 12 | section 2 findings + guide 09 |
| `erd-design-review` (**review-only**) | The ERD checklist and pattern table | `playbook-new-saas-project.md` section 4 |
| `webhook-integration` | Add a provider: signature check, inbox table, idempotent job, replay test | rule 11 + bliv's inbox pattern |
| `write-specs` | RSpec conventions per layer, negative tests, coverage tests | rule 13 + CareSync guides 07 and 09 |

Review-only skills should say "report findings with file and line, do not edit" (the Ombu migration-review example from my search works that way).

### 7.3 Recommended starting set
1. Vendor `graphql-schema` from apollographql (same as the frontend), after reading it.
2. Read `postgresql-table-design` and thoughtbot's audit skill, then decide.
3. Use `rails_ai_agents` rules and `rails-agent-skills` as reading material while writing ours.
4. Write the 7 project skills, **starting with** `security-review-backend`, `graphql-operation`, and `db-migration-review`.

---

## 8. Decisions for you (please answer)

1. **Security findings (section 2):** how do you want to raise them, and do you want me to prepare a short, factual note for your lead?
2. **Layering (L1):** plain services with a Result (my recommendation), or the `interactor` gem like the company?
3. **Folder tree (5.2):** accept as is, or change? In particular `integrations/` instead of provider code under `services/`, and renaming bliv's `forms`.
4. **Rules (section 6):** accept the 16, drop some, or add some? Do you want `.cursor/rules` copies too?
5. **Commit format:** adopt the frontend's `type(scope): message` for the backend, so both repos agree?
6. **Tests:** RSpec (company standard) or Minitest (what you used in CareSync)?
7. **Skills (section 7):** OK to vendor `graphql-schema` after you read it, and to write our own 7 skills?
8. **Review process:** who reviews these rules before they become the template's standard (your lead, a senior engineer)? Rules written only by you and me should be reviewed by someone who runs these systems.

## 9. What happens after you decide
1. I put the approved rules, settings, and `CLAUDE.md` text into files for the new repo (when it exists), plus `docs/architecture.md` and a first `docs/decisions/` set.
2. We write the project skills one at a time, starting with `security-review-backend`.
3. We write guide T01 (project setup) so the rules and tooling are in place **before** the first feature.
4. When you type code, I review it against these rules.

## 10. Takeaway (write your own, 2 lines)
Write what you learned in your own words in your notes, as agreed.

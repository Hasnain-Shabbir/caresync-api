# Rails Mastery Plan: build a HIPAA-style SaaS API ("CareSync")

## Context
You know Node/Express/REST/GraphQL and want to become a job-ready Rails backend engineer for HIPAA-compliant SaaS. Goal: a portfolio-grade API plus the ability to read an unfamiliar Rails codebase, ship production tasks, and debug.

Current state of `store/`: Rails 8.1 / Ruby 3.4.2, full-stack, SQLite, built-in auth generator output (`Authentication` concern, `Session`, `User`, `Current`), a `Product` scaffold, minitest. It is a good **sandbox for Phase 0**, but wrong shape for the real project (not API-only, SQLite, cookie sessions). Decision: keep `store` as the scratchpad, start a fresh `caresync-api` (`rails new --api -d postgresql`) in Phase 1.

## How we work (no long tutorials)
Each step: (1) I give a 5-line concept explainer with a Node/Express analogy, (2) you write the code (I don't type it for you, except boilerplate), (3) I review your diff and quiz you on "why", (4) you record a one-line takeaway in `NOTES.md`. If something is unclear I explain it and point to the exact official guide section, not a whole blog.

Primary references (short, authoritative): Rails Guides (guides.rubyonrails.org), Rails API docs, the Pundit and RSpec READMEs, HHS HIPAA Security Rule summary, OWASP API Security Top 10, "Ruby Style Guide" for idiom. For depth later: *Sandi Metz – POODR* (design), Thoughtbot and Evil Martians blogs (on demand only).

## Node → Rails mental map (reference)
| Express | Rails |
|---|---|
| `app.use` middleware | Rack middleware + `before_action` |
| router file | `config/routes.rb` (`resources`) |
| Sequelize/Prisma | ActiveRecord (migrations, validations, callbacks, scopes) |
| Bull/BullMQ | ActiveJob + Solid Queue/Sidekiq |
| Joi/Zod | strong params + model validations |
| Jest/supertest | RSpec/minitest request specs |
| `process.env`/dotenv | `credentials.yml.enc`, ENV |

## Phases (≈10–12 weeks at ~1–2 hrs/day; reorder freely)

### Phase 0 — Ruby + Rails fundamentals in `store/` (week 1)
- Ruby for JS devs: blocks/procs, `Enumerable` (map/select/reduce/group_by/each_with_object), symbols, hashes, keyword args, modules/mixins, `Struct`/`Data`, `nil` handling (`&.`), duck typing, `frozen_string_literal`. Daily drill in `irb`.
- Rails core: MVC request lifecycle, convention over configuration, autoloading (Zeitwerk), `rails console`, `rails routes`, generators.
- **Exercise:** read the code you already generated (`Authentication` concern, `Current`, `sessions_controller`) and explain each line back to me. Trace one request from route to response.
- **Exit:** can explain `before_action`, concerns, `Current`, `has_secure_password` without notes.

### Phase 1 — Project foundation (week 2)
- `rails new caresync-api --api -d postgresql`, Docker Compose for Postgres, `.ruby-version`, git hygiene, `.env`/credentials, config per environment.
- Tooling: RSpec + FactoryBot + Shoulda, RuboCop (omakase), Brakeman, bundler-audit, GitHub Actions CI running all four. `annotate`/schema comments.
- Conventions: API versioning (`/api/v1`), JSON serialization (Alba or Blueprinter over jbuilder), consistent error envelope, `rescue_from`, health endpoint, request IDs.
- **Exit:** green CI pipeline on an empty-but-real API.

### Phase 2 — ActiveRecord deeply (weeks 2–4)
- Domain: `Organization` (tenant) → `User`, `Patient`, `Provider`, `Appointment`, `ClinicalNote`.
- Migrations done right (reversible, `null: false`, FKs, indexes, `strong_migrations` gem for zero-downtime safety), associations (`has_many :through`, polymorphic), validations vs DB constraints, scopes, enums, callbacks (and why to avoid most), `includes/preload/eager_load`, **N+1** detection (Bullet), `explain`, transactions, locking (optimistic/pessimistic), counter caches, soft delete (`discard`), UUID primary keys.
- Service objects / query objects / form objects: when ActiveRecord models get fat.
- **Multi-tenancy:** `acts_as_tenant` or manual `default_scope` via `Current.organization`; tests that prove tenant A can never read tenant B.
- **Exit:** can read a slow query's `EXPLAIN`, fix an N+1, and write a safe migration on a large table.

### Phase 3 — Authentication (weeks 4–5)
- Understand what Rails 8's generator gave you, then adapt for an API: opaque, DB-backed, revocable bearer tokens (hashed at rest) with expiry and rotation. Learn why this beats a long-lived JWT for HIPAA (instant revocation, idle timeout). Cover JWT trade-offs so you can discuss it in interviews.
- `has_secure_password`, password policy, lockout (`rack-attack`), password reset and email confirmation via ActionMailer + jobs, session listing/"log out everywhere".
- **MFA (TOTP)** with `rotp`; recovery codes. Idle timeout (e.g. 15 min) and absolute timeout.
- **Exit:** full signup/login/logout/reset/MFA flow with request specs including abuse cases (brute force, token reuse after logout).

### Phase 4 — Authorization: roles & permissions (week 6)
- Roles: `admin`, `provider`, `nurse`, `front_desk`, `patient`. Pundit policies + `Scope` for record-level access; `verify_authorized` / `verify_policy_scoped` as safety nets.
- "Minimum necessary" access (HIPAA): field-level visibility per role in serializers; care-team assignment restricts which patients a provider sees; break-glass emergency access with mandatory reason + alert.
- Policy specs as a matrix (role × action × record).
- **Exit:** a policy test matrix that fails loudly if someone adds an endpoint without authorization.

### Phase 5 — HIPAA engineering controls (weeks 7–8)
Understand the *technical safeguards* (§164.312) and map each to code:
- **Access control / unique user IDs** → Phase 3–4.
- **Audit controls:** append-only audit log of every PHI read/write (who, what, when, IP, reason) via `paper_trail`/`audited` or custom `AuditEvent` + `ActiveSupport::Notifications`; tamper-resistance; retention (6 yrs).
- **Encryption at rest:** Active Record Encryption (deterministic vs non-deterministic, blind indexes for search), encrypted DB volume; **in transit:** `force_ssl`, HSTS.
- **PHI hygiene:** `filter_parameters`, scrub logs, error trackers (Sentry `before_send`), no PHI in URLs/emails/job args, safe seed data (never real PHI).
- **Integrity & transmission security:** DB constraints, signed IDs, secure file uploads (Active Storage + virus scan + private bucket + short-lived signed URLs).
- Administrative side to know for interviews: BAA with every vendor (host, email, error tracker), risk assessment, backups/DR tests, incident/breach response, data deletion requests. (Awareness, not legal advice.)
- **Exit:** can answer "how does your system satisfy audit and encryption requirements?" with pointers to code.

### Phase 6 — Production API craft (weeks 8–9)
- Pagination (cursor/keyset, `pagy`), filtering/sorting (Ransack-lite or hand-rolled), idempotency keys, rate limiting, CORS, API docs (rswag/OpenAPI), versioning and deprecation, ETags/conditional GET.
- Background work: ActiveJob + Solid Queue (or Sidekiq/Redis), retries, idempotent jobs, dead-job handling; reminders & email via mailers; webhooks (inbound signature verification, outbound with retries).
- Caching (Rails.cache, Solid Cache), Rack-level concerns, ActionCable only if needed.
- Optional GraphQL layer with `graphql-ruby` (you already know GraphQL; compare dataloader to N+1 tools).
- **Exit:** async appointment-reminder pipeline with retries, documented with OpenAPI.

### Phase 7 — Testing & quality discipline (continuous, formalized week 9)
- Testing pyramid in Rails: model specs, request specs (the main workhorse), policy specs, job/mailer specs, a few end-to-end flows. FactoryBot traits, `travel_to`, WebMock/VCR for third parties, SimpleCov gate (~90%).
- TDD a feature end to end; characterization tests before refactoring legacy code.
- **Exit:** CI blocks merges below coverage/lint/security thresholds.

### Phase 8 — Debugging, reading legacy code, performance (week 10)
This is the "take on tickets at a real company" phase.
- Debugging toolkit: `debug` gem breakpoints, `rails console` on a prod-like DB, `binding.irb`, `ActiveRecord::Base.logger`, `caller`, `method(:x).source_location`, `pry`-style spelunking, reading gem source (`bundle open`).
- **Exercises:** I will inject realistic bugs into a copy (N+1, race condition, wrong scope leaking tenant data, callback side effect, timezone bug, flaky job) — you find and fix them with only the logs/tests.
- Reading unfamiliar codebases: start from routes → controller → model → callbacks → jobs; use `rails stats`, `rails notes`, grep recipes, Rails' own source as reference.
- Performance: `rack-mini-profiler`, `derailed_benchmarks`, `pg_stat_statements`, slow-query indexing, memory bloat basics, puma threads/workers tuning.
- Ruby gotchas: mutation/`dup`, `||=` memoization pitfalls, thread-safety, monkey-patching/`prepend`, metaprogramming (`define_method`, `method_missing`, `Concern`, `class_eval`) so DSL-heavy code stops looking like magic.

### Phase 9 — Ship it (weeks 11–12)
- Dockerfile (Rails 8 ships one), Kamal deploy to a VPS (or Render/Fly/AWS) with HIPAA-eligible hosting discussion (AWS/GCP BAA), zero-downtime deploys, migrations in deploy, secrets management, structured JSON logging (lograge), monitoring (Sentry/Honeybadger, uptime), backups + restore drill, runbook in the repo.
- Portfolio polish: README with architecture diagram, threat model, HIPAA control mapping table, ADRs (architecture decision records), seed script, Postman/OpenAPI collection, short Loom-style walkthrough script for interviews.
- **Exit:** public repo + live (non-PHI) demo + interview-ready story.

## Deliverable checklist for the final project
Multi-tenant API · token auth + MFA · RBAC with Pundit · audit log · encrypted PHI fields · background jobs · OpenAPI docs · ≥90% coverage · CI (rspec, rubocop, brakeman, bundler-audit) · Docker/Kamal deploy · HIPAA control-mapping doc.

## Verification (how we know it's working)
- Every phase ends with its **Exit** criterion, demonstrated by passing specs and by you explaining the design to me unprompted.
- Weekly "mock interview" round: 5 Rails questions + one code-reading task from the real codebase.
- Final: a cold-start test, where I give you an unfamiliar Rails repo and a bug ticket and you fix it with a PR.

## First actions once approved
1. Phase 0 today: read through `app/controllers/concerns/authentication.rb`, `sessions_controller.rb`, `models/current.rb` with me; ruby drill set #1 in `irb`.
2. Create `NOTES.md` and a `ROADMAP.md` checklist in the new repo mirroring these phases.

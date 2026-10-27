# Learning plan: from "basics" to production Rails (databases first)

Written for you, to decide **what to add and in what order**. Simple English, Node/Express comparisons. Pick tracks, then I turn each pick into a guide in the usual format (why, steps, tests, self-check) and you type the code.

**What this is based on:** the course outline you pasted, plus a read of `db/schema.rb` and the three models. **Nothing here was run.** Where I say "finding", I read it in the schema. Time estimates are my guesses.

---

## 1. Where the course outline lands in Rails

You already did most of the "Express" half. The gap is the **database half** and the **production half**.

| Course section | Rails equivalent | Status in CareSync |
|---|---|---|
| How the web works, HTTP, API vs static | same ideas | known |
| Node internals, event loop, streams, modules | Puma threads, the GVL, Active Job, autoloading (Zeitwerk) | **gap**: concurrency model (Track F) |
| Promises, async/await | no direct equivalent (threads and jobs instead) | skip, replaced by Track F |
| Express, routing, middleware, env vars | Rails routing, Rack middleware, credentials | done |
| MongoDB and Mongoose basics | PostgreSQL and ActiveRecord | basics only (**Tracks A, B**) |
| Filtering, sorting, pagination, aggregation pipeline, virtuals, validation | scopes, `where`, `group`, window functions, CTEs, connections | **gap** (**Track C**) |
| Error handling | `rescue_from`, errors as data | done |
| Auth, JWT, roles, reset, rate limit, security headers | Devise, Pundit, rack-attack | done (MFA and audit log not done) |
| Data modelling, references, indexes, geospatial | schema design, FKs, indexes, PostGIS | **gap** (**Tracks A, D, E**) |
| Pug server rendering | not needed (API only) | skip |
| Uploads, email, Stripe | Active Storage, Action Mailer, webhooks | mail done, rest optional |
| Deployment, SIGTERM, CORS, webhooks | Kamal, graceful shutdown | CORS done, deploy not (**Track F**) |

Course lesson that maps most directly to your next level: **"Data Modelling" and "Aggregation Pipeline"** are the two sections where Postgres is much stronger than Mongo, and you have not touched either yet.

---

## 2. Finding: what CareSync's own schema teaches (a ready-made first exercise)

From reading `db/schema.rb` (4 tables: organizations, users, patients, allowlisted_jwts). These are real review points, not bugs that break today:

| # | Finding | Why it matters | Fix idea |
|---|---|---|---|
| 1 | `patients` has `index_patients_on_organization_id` **and** a composite index starting with `organization_id`. | The single-column index is redundant: Postgres can use the composite for the same lookups. Extra index = slower writes, more disk. | Drop the single one in a migration (after checking with `EXPLAIN`). |
| 2 | `users.role` is a plain string. The Rails `enum` validates it, but **the database accepts any value**. | A raw SQL insert, a console typo, or a future bug can write `role = "admn"`. Validations are not constraints. | A `CHECK (role IN (...))` constraint (or a Postgres enum type). |
| 3 | `users.email` is globally unique. | Fine for one email = one person across all clinics. If a nurse works at two clinics, they cannot have two accounts. This is a **design decision**, not a mistake. Write it down. | Decide and document. Alternative: unique on `(organization_id, email)`. |
| 4 | Tenancy is enforced only in Ruby (`current_organization`). The DB would happily link rows from different clinics once we add more tables. | Today only `patients` has `organization_id`, so it is safe. The moment you add `appointments` (patient plus provider) a bug can attach a patient from clinic A to a provider from clinic B. | **Composite foreign keys** `(patient_id, organization_id)`. Needs a unique index on `patients(id, organization_id)`. Big learning topic. |
| 5 | `date_of_birth` (PHI) and names are plain text columns. | "HIPAA-style" usually means encryption at rest for PHI fields. Rails has `encrypts`. Trade-off: you cannot `WHERE` or index encrypted columns freely. | Track B: `encrypts`, deterministic vs non-deterministic. |
| 6 | Patients are hard deleted. | A medical record you cannot recover or audit. Known gap already. | Soft delete (`discarded_at`) plus a partial index `WHERE discarded_at IS NULL`. |
| 7 | No `updated_by` or audit trail. | You cannot answer "who changed this patient". Known gap already. | Audit table (own design, or the `paper_trail` / `audited` gems, compare them). |
| 8 | All ids are sequential `bigint`. | Guessable ids (`/patients/42`). Tenancy returns `NOT_FOUND` so it is safe today, but for PHI many teams prefer UUIDs. | Learn the trade-offs: UUID v4 vs v7, index size, ordering. |

Findings 1 and 2 are a 20-minute migration exercise. Findings 4 and 5 are the real learning.

---

## 3. The tracks

Each track: **why**, **topics**, **hands-on in CareSync**, **done when**. Priority is my recommendation for "confident on production apps".

### Track A. Database design with PostgreSQL (priority: MUST, do first)
**Why:** every later problem (slow queries, wrong data, tenant leaks) starts as a design problem. Mongo let you skip this. Postgres rewards it.

Topics:
- Normal forms in plain words, when to denormalize on purpose.
- Constraints as the last line of defence: `NOT NULL`, `UNIQUE`, `FOREIGN KEY` (and `ON DELETE` choices), `CHECK`, **exclusion constraints**.
- Types: `text` vs `varchar`, `timestamptz` vs `timestamp`, `date`, `numeric` for money (never float), `jsonb` (when yes, when no), arrays, enums, ranges.
- Keys: bigint vs UUID, natural vs surrogate keys, composite keys and **composite foreign keys for tenancy**.
- Relationship patterns: one-to-many, many-to-many with a join table that has its own columns, polymorphic (and why people regret it), self-references.
- Soft delete, history tables, audit tables.
- Naming and conventions Rails expects (and how to break them safely).

Hands-on: fix findings 1, 2, 4, 6 in section 2. Design the **appointments** extension (section 4) on paper first, then in a migration.
Done when: you can draw the ER diagram of a new feature, say which constraints go in the DB vs the model, and defend each.

### Track B. ActiveRecord, deeper (priority: MUST)
**Why:** you used `belongs_to`, `has_many`, validations. Production code leans on the parts below.

Topics:
- `has_many :through`, `has_one`, polymorphic, **STI vs delegated types** (Rails 8 favourite), and why to be careful with STI.
- Scopes vs class methods, query objects, keeping models thin.
- Callbacks: which are safe, which cause pain (`after_save` side effects, `after_commit` for jobs).
- Validations vs DB constraints (uniqueness race conditions: why `validates :uniqueness` alone is not enough).
- **Transactions and locking**: `transaction`, isolation levels, optimistic locking (`lock_version`), pessimistic (`lock!`, `FOR UPDATE`), `with_lock`. Example: two receptionists book the same slot.
- Counter caches, `touch`, `insert_all` / `upsert_all`, `update_all` and what they skip.
- `normalizes`, the attributes API, `encrypts` (links to finding 5), `strict_loading` (turns N+1 into an error).
- Active Record and **connection pool vs Puma threads** (a classic production incident).

Hands-on: add `encrypts` to `date_of_birth` and see what breaks (searching, fixtures, tests). Write the "double booking" problem both with a lock and with an exclusion constraint, compare.
Done when: you can explain what happens to a callback inside a rolled-back transaction, and show a race condition test.

### Track C. Complex queries (priority: MUST, this is the "aggregation pipeline" gap)
**Why:** reports, dashboards, and "smart lists" are where real apps live. This is the Mongoose aggregation section, but in SQL.

Topics (ordered easy to hard):
1. `where`, `or`, `not`, `joins` vs `left_joins`, `includes` vs `preload` vs `eager_load` (when each one fires which SQL).
2. `group`, `having`, `count/sum/avg`, `select` with expressions, `pluck`, `distinct`.
3. **Subqueries and `EXISTS` / `NOT EXISTS`**: "patients with no appointment in 90 days".
4. **`DISTINCT ON`** and **window functions** (`ROW_NUMBER`, `LAG`, running totals): "last appointment per patient".
5. **CTEs** (`.with`, recursive CTEs for trees).
6. Ranges, date math, time zones (`date_trunc`, `generate_series` for gap filling).
7. Search: `ILIKE` and why it is slow, `pg_trgm` for typo-tolerant search, full-text search (`tsvector`).
8. **Pagination**: offset vs **keyset (cursor)**, why offset gets slow, how it maps to GraphQL connections.
9. Reading `EXPLAIN (ANALYZE, BUFFERS)`: seq scan vs index scan, why the planner ignores your index.
10. Raw SQL safely (`sanitize_sql`, bind params), Arel basics, `find_each` for big tables.

Hands-on (all on CareSync data, section 4 gives the tables): write each query in `psql` first, then as ActiveRecord, then expose one as a GraphQL field. Check each with `EXPLAIN` before and after an index.
Done when: you can take "show me X" from a product person, write it in SQL, and say which index it needs.

### Track D. Migrations and schema in production (priority: SHOULD)
**Why:** the first outage most Rails teams have is a migration locking a big table.

Topics: what locks a table (adding a column with default, adding an index, adding a FK), `CREATE INDEX CONCURRENTLY` (`algorithm: :concurrently`), `add_foreign_key ... validate: false` then `validate_foreign_key`, backfilling in batches, expand then contract (rename a column without downtime), the `strong_migrations` gem, `schema.rb` vs `structure.sql`, reversible migrations, seeds vs fixtures, multi-database setup (you already have cache/queue DBs).
Hands-on: write the safe version of dropping the redundant index and adding the `role` CHECK constraint (add `NOT VALID`, then validate).
Done when: you can read a migration and say "this would lock the table for N seconds on 10 million rows".

### Track E. Performance and observability (priority: SHOULD)
Topics: finding slow queries (`pg_stat_statements`, slow query log, your query log tags are already on), `EXPLAIN`, N+1 tools (Bullet, Prosopite, `strict_loading`), indexes (partial, composite order, covering, GIN/GiST), caching (Solid Cache, fragment vs low-level), counter caches, connection pool sizing, load testing a GraphQL endpoint (what depth/complexity numbers mean under load).
Hands-on: seed 100k patients, run the slow query, fix it, show before/after numbers. (This also tests the guide 09 complexity numbers on real data.)
Done when: you can show a query's plan before and after and explain the change.

### Track F. Production operations in Ruby (priority: SHOULD, partly replaces the Node internals section)
Topics:
- **The concurrency model** (your event loop section): Puma workers and threads, the GVL (what it blocks and what it does not), why background work goes to Solid Queue, thread safety (shared state, `Current` attributes).
- Config: credentials vs env vars, per-environment config, 12-factor.
- Logging: structured logs, log levels, what must never be logged (guide 09 covered the start).
- Error tracking and health checks (`/up`), graceful shutdown (SIGTERM, drain requests, finish jobs).
- Deploy with **Kamal** (Docker, zero-downtime), running migrations on deploy, backups and restore drills (a backup you never restored is not a backup).
- Dependency hygiene: `bundler-audit`, Dependabot, upgrade cadence.
Hands-on: deploy CareSync to a cheap VM or a local Docker setup with Kamal; kill a worker mid-job and see what happens.
Done when: you can describe what happens to an in-flight request and an in-flight job during a deploy.

### Track G. GraphQL, next level (priority: MUST for you, GraphQL is the main target)
Topics:
- **Connections and cursor pagination** (guide 09 flagged `patients` returning everything).
- **Dataloader patterns beyond `has_many`**: counts, aggregates, `has_many through`, keyed lookups (N+1 for computed fields).
- Mutation design: input objects, payload types, idempotency keys, optimistic concurrency in mutations (ties to Track B).
- Schema evolution: deprecations, additive changes, naming conventions, versioning without `/v2`.
- Errors: expected vs unexpected, error masking in production, the `extensions` contract.
- Persisted queries and allowlisting (a stronger answer than depth limits).
- Field-level authorization at scale, **testing the GraphQL schema** (snapshot of schema dump, breaking-change check).
- Subscriptions (optional), file uploads (optional).
Hands-on: convert `patients` to a connection with `first`/`after`, add `appointmentCount` with a dataloader, add a schema dump check to the test suite.
Done when: no list field returns unbounded rows and a schema change that breaks clients fails CI.

### Track H. Security and compliance depth (priority: SHOULD, for the HIPAA story)
Topics: field encryption (`encrypts`), audit log design, soft delete and retention, MFA/TOTP, session idle timeout (the "later" guide), secrets rotation, least-privilege DB roles (app user cannot `DROP`), backups encryption, PHI in logs and error trackers, a basic threat model and a control mapping table (this is plan item 5, the README).
Done when: the README's control table points at real code or config for every row.

### Track I. Testing depth (priority: LATER)
Topics: fixtures vs factories (you use fixtures, learn when factories win), testing constraints at the DB level (insert invalid raw SQL, expect failure), testing migrations, testing jobs and mailers (you started), time travel, flaky test causes, coverage that means something (your "coverage test" idea from guide 07 is the good kind), CI setup.

---

## 4. A small domain to practice on (so the queries are real)

Today CareSync has only patients and users, so there is almost nothing to query. A minimal extension gives every track a real exercise:

- `appointments`: `organization_id`, `patient_id`, `provider_id` (a user), `starts_at`, `ends_at`, `status`, `reason`
- `visit_notes`: `appointment_id`, `author_id`, `body` (encrypted), `signed_at`
- optional later: `medications`, `insurance_plans` (a many-to-many with extra columns)

Queries this unlocks (use them as drills, solutions come in the guides):
1. Patients with **no** appointment in the last 90 days (`NOT EXISTS`).
2. The **most recent** appointment per patient (`DISTINCT ON`, then a window function, compare plans).
3. Appointments per provider per day, **including days with zero** (`generate_series` plus left join).
4. **Overlapping** appointments for one provider, then prevent them with an **exclusion constraint** on a `tstzrange` (the best Postgres feature to learn for scheduling).
5. Cancellation rate per provider with `FILTER (WHERE status = 'cancelled')`.
6. Search patients by name with typos (`pg_trgm`).
7. Paginate a 100k-row appointment list with a keyset cursor.
8. A running total of appointments per week (window function).

This also forces the tenancy question from finding 4 (composite foreign keys) and the double-booking question from Track B.

**Decision for you:** extend CareSync with this, or build it in a separate practice app? My recommendation: **extend CareSync**. Auth, tenancy, policies, and tests already exist, so each new table is a full vertical slice using [guide-adding-a-crud-resource.md](guide-adding-a-crud-resource.md), and you practise the whole workflow, not just SQL. Keep it small (two tables) so it does not eat your submission time.

---

## 5. Suggested order (and how it fits your dates)

Today is 2026-10-22, the submission project is due 2026-10-30.

| When | What |
|---|---|
| Next (1 to 2 days) | Finish CareSync's open plan items: remove the REST API, finish guide 07 sections 4.2 and 4.3, write the project README. |
| Before the submission project starts | **Track A basics plus Track C items 1 to 4** (2 short guides). These are the parts you will most likely use in the submission, and they are the ones you said you want. |
| During the submission project | Apply them there. Use the schema review (section 2) as your checklist for your own design. |
| After submission | Track B (locking, `encrypts`), Track C rest, Track G (connections), then D and E, then F and H. Track I last. |

If time is short, cut from the bottom: I, then F, then H.

**Proposed guides (names only, each one is a guide in the usual format):**
- Guide 10: Schema review and constraints (findings 1, 2, 3 with migrations and tests)
- Guide 11: Querying with ActiveRecord and SQL (Track C, items 1 to 4, with the appointments tables)
- Guide 12: Composite foreign keys, tenancy in the database, and exclusion constraints
- Guide 13: Indexes and `EXPLAIN` (read plans, fix a slow query)
- Guide 14: Pagination: keyset cursors and GraphQL connections
- Guide 15: Locking, transactions, and race conditions
- Guide 16: Encrypting PHI with `encrypts` (and what it breaks)
- Guide 17: Safe migrations for production
- Later: deploy with Kamal, concurrency model, audit log, soft delete

## 6. How to study (same method as before)
Try first, read the guide second, write a 2-line takeaway in your own words. For database topics add one rule: **run every query in `psql` with `EXPLAIN` before you trust it**. Seeing the plan is how the learning sticks.

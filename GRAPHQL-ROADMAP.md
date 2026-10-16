# CareSync: GraphQL production roadmap

Supersedes the Phase 1 to 6 order in [ROADMAP.md](ROADMAP.md). The REST `Organization` CRUD (`/api/v1/organizations`) stays in the repo as the baseline and comparison. Everything below is built on GraphQL.

How we work: I write boilerplate and a short doc per step, you write the core logic, I review the diff and ask the self-check questions, you add takeaways to [NOTES.md](NOTES.md). Stack: Rails 8.1 API, Ruby 3.4.2, PostgreSQL, Minitest, graphql-ruby.

## Steps

| # | Step | Main topics | Exit criterion |
|---|---|---|---|
| 1 | **Domain models** | `User`, `Patient` migrations, associations, DB constraints, validations, fixtures | model tests green, schema reviewed |
| 2 | **GraphQL foundation** | graphql-ruby install, schema, `/graphql` single endpoint, types, queries (`organizations`, `organization(id:)`), query tests | queries work in a test and via curl |
| 3 | **Mutations and errors** | input types, `create/update/deleteOrganization`, errors-as-data (`userErrors`) vs top-level errors, `rescue_from` in the schema | CRUD parity with the REST API |
| 4 | **Relations and N+1** | nested fields, `dataloader`, Bullet, query depth/complexity limits | nested query runs in a constant number of SQL queries |
| 5 | **Authentication** | `bcrypt` + `has_secure_password`, `Session`/API token table (hashed at rest, expiry, revocation), `login` / `logout` mutations, `context[:current_user]` | login, use token, logout, token rejected after logout |
| 6 | **Multi-tenancy** | `Current.organization`, tenant-scoped queries, tenant isolation tests | tenant A can never read tenant B (tested) |
| 7 | **Authorization** | roles (`admin`, `provider`, `nurse`, `front_desk`), Pundit policies per resolver and mutation, field-level visibility | role x action test matrix |
| 8 | **Hardening** | `rack-attack` (rate limits, login lockout), CORS, query limits, introspection off in production, `filter_parameters`, request IDs | abuse-case tests pass |
| 9 | **HIPAA controls** | audit log of PHI reads and writes, Active Record Encryption for PHI fields, PHI-safe logs and errors, session idle timeout, MFA (TOTP) | control-mapping table in the README |
| 10 | **Production readiness** | structured logging (lograge), error tracking with scrubbing, jobs (Solid Queue), CI gates (coverage, brakeman, rubocop, bundler-audit), Docker/Kamal, seeds, runbook | green CI, deployable image |

## Decisions made
- Stay on Minitest (no RSpec switch).
- Primary keys stay `bigint` for now. Revisit UUIDs (better for exposed IDs) before Patient data matters. Changing later means a migration on every table.
- `User` columns include `password_digest` from the start, and the `bcrypt` gem is added in step 5.
- Roles as a Rails `enum` on `User` (step 7).
- REST stays unauthenticated and isn't extended further.

## Open decisions (decide at the step)
- Token format in step 5: opaque DB-backed token (recommended for revocation and idle timeout) vs JWT.
- Soft delete (`discard`) vs hard delete for `Patient` (step 9).
- Relay-style connections (cursor pagination) vs plain lists in step 4.

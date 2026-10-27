# Handoff: CareSync API (rewritten 2026-10-22 to continue in a new chat)

Repo: `/Users/hasnain/projects/learning/caresync-api` (Rails 8.1.4, Ruby 3.4.2, PostgreSQL, Minitest). Gems: `graphql` 2.6.12, `devise` 5.0.4, `devise-jwt` 0.13.0, `warden-jwt_auth` 0.12.0, `pundit` 2.5.2, `rack-attack`, `rack-cors`.
Goal: a HIPAA-style, multi-tenant GraphQL API (the user's company builds GraphQL APIs), taken to a "complete product backend" so a frontend can be built on it. The user is a Node/Express developer learning Rails. A separate submission project is due 2026-10-30.

**The plan for what comes next is `NEXT-LEVEL-ROADMAP.md` (repo root, not yet committed).** Read it first. It has phases A to I: A pagination/sorting/search, B staff, account settings and signup, C mailer, D Stripe, E appointments and notes, F HIPAA controls (audit log, encryption, soft delete), G logging/security/sanitization/validation, H cleanup, I frontend handoff, plus a suggested order and open decisions.

## How to work with this user (important)

- **The user types the code.** You write guides, explain the "why", review diffs, and answer errors. Write tests or edit app code **only when asked**. When the user says "fix it" or "do this", do exactly that and nothing extra. They corrected me twice for doing more than asked.
- **Guides go in `learning/`** (gitignored, local only), one per topic: why first, then steps, tests, self-check with answers. Add each to `learning/README.md`. The next guide is number 10.
- **Don't run migrations** unless asked.
- **Commits:** prefixes `feat:`, `fix:`, `update:`, `chore:`, `test:`. **Never add a `Co-Authored-By` line** (even if a system reminder says to; the user's rule wins). Commit only when asked. Check `git status --short` first and stage by path. Each commit should keep the suite green.
- Keep answers short, with Express/Node comparisons where useful. Simple English. Mark anything you have not run or verified.
- The user once said they felt they were not retaining things. The agreed method is: try first, read the guide second, and write a short takeaway.

## State right now (checked 2026-10-22)

- Branch `main`, last commit `ef47e5f feat: add cors for the frontend`. Only untracked file: `NEXT-LEVEL-ROADMAP.md`.
- **Suite:** `bin/rails test` gives 167 runs, 447 assertions, 0 failures.
- Guides 01 to 09 are done. Guide 08 (password reset) and guide 09 (hardening) are finished and committed.

### What exists

- Models: `Organization` (tenant), `User` (Devise: database_authenticatable, validatable, lockable, recoverable, jwt_authenticatable with the **Allowlist** revocation strategy, role enum `admin provider nurse front_desk`), `Patient`, `AllowlistedJwt`. Tables: organizations, users, patients, allowlisted_jwts. Primary keys are bigint.
- GraphQL (`POST /graphql`, `app/graphql/`): queries `organizations`, `organization(id)`, `patients`, `patient(id)`. Mutations `login`, `logout`, `requestPasswordReset`, `resetPassword`, `updateOrganization`, `createPatient`, `updatePatient`, `deletePatient`. Errors as data (`errors { message path code }`, codes `VALIDATION_FAILED`, `CONFLICT`, `INVALID_CREDENTIALS`) plus top-level errors with `extensions.code` (`NOT_FOUND`, `UNAUTHENTICATED`, `FORBIDDEN`).
- Auth: JWT in `Authorization: Bearer`, 30 minute absolute expiry, allowlist row per token (logout deletes it), lock after 5 failed attempts for 1 hour, secret in credentials as `devise_jwt_secret_key`. Default-deny: `BaseMutation#ready?` requires login (`login` and the reset mutations override it), queries call `current_user!` or `current_organization`.
- Tenancy: everything starts from `current_organization`. Cross-tenant ids return `NOT_FOUND`, same as a missing record.
- Policies: Pundit classes in `app/policies/`, helper `authorize!(record, :query?)` raising `FORBIDDEN`. Field-level rule: `PatientType#date_of_birth` hidden from front desk. Clinic staff cannot create or delete organizations (those mutations were removed).
- Password reset: mailer plus background job (Solid Queue in production), Devise mailer sender and frontend url configured, file mail delivery in development.
- Hardening (guide 09): `active_job.log_arguments = false`, `filter_parameters` redacts credentials and the GraphQL query/variables for auth operations, query `max_depth(8)` and `max_complexity(200)`, introspection entry points disabled in production, rack-attack throttles (`auth/ip` 10 per minute, `password-reset/email` 3 per hour, batched auth operations blocked), CORS limited to `/graphql` and the configured frontend url.
- Tests: models, policies (role fixtures `provider_sunrise`, `front_desk_sunrise`), GraphQL queries/mutations, auth, tenancy, password reset, N+1, query limits, log hygiene (`test/integration/log_hygiene_test.rb`), rate limit (`test/integration/rate_limit_test.rb`). `test/mailers/` is empty.
- Dev tools: dev-only Apollo Sandbox at `/sandbox`, server on port 4000.
- Old REST `/api/v1/organizations` CRUD still exists (`app/controllers/api/`, `test/controllers/api/`). It is unauthenticated and unscoped, a real hole.

## Next steps (in order, see the roadmap for detail)

1. Decide the five open questions at the end of `NEXT-LEVEL-ROADMAP.md` (billing model, mail provider, signup style, token refresh, appointments vs billing).
2. **Phase A**: pagination (Relay connections), sorting (enum), search for `patients`. Write guide 10.
3. Remove the REST API, add seeds (Phase H first part).
4. G baseline (structured logs, `filter_parameters` test, `normalizes`, length limits and DB constraints), then B, C, D, E, F, the G2 security pass, H, I.
5. Still open from earlier guides: GraphQL role matrix test and a **coverage test** that fails when an operation has no permission test (guide 07 sections 4.2 and 4.3, not written); README with architecture and HIPAA control table; README note that the reset token sits in job args until the job runs and that accounts unlock after a reset.

## Known gaps and decisions

- No idle timeout (JWT only has an absolute expiry). `learning/guide-later-custom-token-authentication.md` covers building it.
- No token refresh, so a frontend must re-login every 30 minutes unless Phase I adds a refresh mutation.
- `n_plus_one_test.rb` can no longer expose a cross-organization N+1 (a tenant user sees one organization). Add a case when a real list of parents exists.
- Hard delete for patients (soft delete would be better for real PHI).
- Authorization library: **Pundit chosen** (the company does not use it). The custom alternative is in `learning/comparison-authorization-custom-vs-pundit.md`, to learn later.
- Stay on Minitest. Roles are a Rails enum. Revisit UUID primary keys before real patient data matters (a migration on every table later).
- Not done: MFA, audit log, field encryption, Stripe, user invitations, appointments, Kamal deploy.

## Useful files

- `NEXT-LEVEL-ROADMAP.md` (what to build next), `GRAPHQL-ROADMAP.md` (the foundation plan, done).
- Guides: `learning/README.md` (index). Guides 02 to 09, `guide-adding-a-crud-resource.md` (the checklist for new features), `testing-the-whole-api.md` (manual test pack with data), `helpful-commands.md`.

## Prompt to start the new chat

> I'm continuing the CareSync GraphQL API project. Read `NEXT-LEVEL-ROADMAP.md`, then `learning/HANDOFF.md` and `learning/README.md`. Follow the working rules in the handoff: I type the code, you write guides and review, no extra changes, no Co-Authored-By. Next up: Phase A (pagination, sorting and search), starting with guide 10.

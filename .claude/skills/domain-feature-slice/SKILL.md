---
name: domain-feature-slice
description: Plan and build a whole new feature end to end (table, model, policy, service, GraphQL, tests). Run manually with /domain-feature-slice when starting a new resource.
disable-model-invocation: true
---

# Build a feature as one vertical slice

Use for a new resource or capability that touches the database through the API. For a single operation, use `graphql-operation`. For table design, also open `postgresql-table-design`.

## 1. Ask first (write the answers down)
- Who owns the data: always an organization (tenant table)? Which roles read, create, change, delete?
- Is any field PHI or otherwise sensitive? (encryption, hidden for roles, never logged)
- Lifecycle: which statuses, who moves them, can they go backwards?
- Deletion and retention: hard delete, archive timestamp, or anonymize?
- Search, filters, sort, and expected size (decides indexes and pagination).
- Anything external (email, provider)? That runs in a job.

## 2. Design on paper before code
Table and columns, `NOT NULL`, uniqueness, `CHECK` on every status, foreign keys with `ON DELETE`, indexes for each screen query, composite tenant key for children. Show it to the owner.

## 3. Build in this order (owner types the code unless asked)
1. Migration (write it, **do not run** it unless asked). Run `db-migration-review` on it.
2. Model: associations, validations that mirror the constraints, string enum with `CHECK`.
3. Policy and policy tests (default deny, one method per action).
4. Service (one use case, returns a `Result`) and its tests.
5. GraphQL type, query, mutation (use `graphql-operation`).
6. Tests: matrix per role, cross-tenant, validation, N+1, list complexity.
7. Hardening check: logs, errors, limits (see `security-review-backend`).

## 4. Finish
- `bin/rails test`, `bin/rubocop`, `bin/brakeman -q`.
- Update the manual test pack and add a learning guide in `learning/` if asked.
- Propose commits (one concern each, suite green after each). Commit only when asked.

---
name: write-tests
description: CareSync Minitest conventions and the required cases for operations, services, policies, and security paths. Use when creating or editing files in test/.
paths:
  - "test/**"
---

# Writing tests (Minitest)

Read `.claude/rules/testing.md`. Write tests only when asked. When asked, follow this.

## Where
`test/` mirrors `app/`: `test/graphql/` (operations), `test/policies/`, `test/models/`, `test/services/` (target), `test/integration/` (middleware like rate limiting and logs).

## Helpers that exist
- `graphql_context(user)` for calling the schema directly: `CaresyncApiSchema.execute(QUERY, variables:, context: graphql_context(users(:nurse_sunrise))).to_h`
- `auth_headers(user)` for request tests: `post graphql_url, params: { query: }, as: :json, headers: auth_headers`
- Fixtures: users `admin_sunrise`, `provider_sunrise`, `nurse_sunrise`, `front_desk_sunrise` (password is `password`), `organizations`, `patients`.

## Cases every operation needs
1. Success.
2. Validation failure (error `code` and `path`).
3. Unauthenticated.
4. Forbidden, for each role that must not do it.
5. Cross-tenant (another organization's record is `NOT_FOUND`).
6. List operations: no N+1 and the complexity multiplier.

## Security paths need negative tests
Garbage, expired, and post-logout tokens. Wrong password. Unknown email returns the same response as a known one. Reused or expired reset token. Replayed code.

## Rules
- Keep the coverage tests (operations versus permission tests, list fields versus complexity). Never loosen them.
- No real network, no `sleep`. Use `travel` for time.
- Rate-limit tests swap in a memory store and restore the null store in `teardown`.
- Assert behavior and error codes, not private methods.
- Add role fixtures rather than editing existing ones.

## Run and report
```
bin/rails test
bin/rails test test/graphql/auth_test.rb
bin/rubocop
bin/brakeman -q
```
Report real output. Never claim green without running.

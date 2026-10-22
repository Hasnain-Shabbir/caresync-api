---
paths:
  - "test/**"
---

# Testing (Minitest)

CareSync uses Minitest and fixtures. (The future SaaS template uses RSpec. Keep the same ideas, only the syntax differs.)

- `test/` mirrors `app/`. Test through the layer's public face: GraphQL request tests for operations, unit tests for services, policy tests, model tests for constraints.
- Every operation has: a success case, a validation failure, an unauthenticated case, a forbidden case, and a **cross-tenant** case.
- Security paths have **negative tests**: forged or garbage token, expired token, token after logout, replayed or expired code, enumeration (same response for known and unknown email).
- Keep the **coverage tests** (operations versus permission tests, list fields versus complexity multiplier). Add to them, never loosen them.
- Fixtures: every fixture user's password is `password`. Add role fixtures instead of editing existing ones.
- No real network and no sleeping. Use `travel` for time.
- Rate-limit tests swap in a memory store and restore the null store afterwards.
- Run the whole suite, `bin/rubocop`, and `bin/brakeman -q` before saying a change is done. Report failures with their output. Never claim green without running.

## Commands
```
bin/rails test
bin/rails test test/graphql/auth_test.rb
bin/rubocop
bin/brakeman -q
```

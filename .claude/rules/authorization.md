---
paths:
  - "app/policies/**"
  - "app/graphql/**"
---

# Authorization and tenancy

- Pundit policies, **default deny** (`ApplicationPolicy` allows nothing). A rule is explicit or it does not exist.
- One policy per resource. Roles come from `User#role` (`admin`, `provider`, `nurse`, `front_desk`). Do not scatter `if user.admin?` checks through mutations or types. Ask the policy.
- Tenancy: start from `current_organization`. `Patient`, and any later tenant table, is reached through it. Never `Patient.find(id)`.
- A record in another organization returns the same `NOT_FOUND` as a missing record, never `FORBIDDEN`.
- Field-level rules (a field hidden for a role) are a policy method used by the type, with a test.
- Permissions are policy methods, not boolean columns on `users`.
- Changing a role's permissions means updating the policy **and** its policy test **and** the permission matrix.

## Tests that must exist
- Policy tests per resource (`test/policies/`).
- Cross-tenant tests (`test/graphql/tenancy_test.rb`).
- A role-by-operation matrix at the GraphQL level, and a coverage test that fails when an operation has no permission test.

## Status in CareSync
Policy and tenancy tests exist. The GraphQL-level matrix and the coverage test (guide 07, sections 4.2 and 4.3) are **not written yet**.

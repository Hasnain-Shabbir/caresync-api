---
name: security-review-backend
description: Review-only security check of CareSync authentication, authorization, tenancy, logging, CORS, and production settings. Use when changing auth, policies, GraphQL access, or config.
paths:
  - "app/graphql/concerns/authenticatable.rb"
  - "app/graphql/mutations/login.rb"
  - "app/graphql/mutations/logout.rb"
  - "app/graphql/mutations/*password*.rb"
  - "app/controllers/graphql_controller.rb"
  - "app/policies/**"
  - "config/initializers/**"
disallowed-tools: Edit Write
---

# Backend security review (report only, never edit)

Read `.claude/rules/security-and-privacy.md` and `authentication-and-sessions.md` first. Report findings with file and line and a severity. Do not change files. **Never test a weakness against a real system. Reproduce it in a test or reason from the code.**

## Checklist
**Authentication and sessions**
- [ ] No `JWT.decode` with verification off anywhere (search the whole app).
- [ ] Tokens revocable (allowlist row). Logout, password change, reset, archive, revoke delete them.
- [ ] Login, reset, and lockout give one message for unknown email, wrong password, and locked account.
- [ ] Reset tokens single use and short lived. Passwords never logged.

**Authorization and tenancy**
- [ ] Every operation calls a policy. Default deny holds (`ApplicationPolicy`).
- [ ] Every query starts from `current_organization`. No global `find`.
- [ ] Cross-tenant ids return `NOT_FOUND`.
- [ ] Field-level hiding exists where a role must not see a field.

**Data and logs**
- [ ] `filter_parameters` covers the GraphQL `query` text and string `variables`.
- [ ] No secrets, codes, or PHI in job arguments, logs, exception notifiers, or error messages.
- [ ] Sensitive fields: `encrypts`, with keyed or deterministic search, never an unkeyed hash.
- [ ] Authentication emails: stored copies are redacted and have a retention period.

**Configuration**
- [ ] CORS has one explicit origin, never `*`.
- [ ] Production: introspection off, depth and complexity limits, throttling on anonymous operations, `force_ssl`.
- [ ] No secrets in code, Docker build args, image `ENV`, or fixtures. No hard-coded emails or ids.
- [ ] No unauthenticated endpoint or dev tool reachable in production (the legacy REST routes count).

**Evidence**
- Run `bin/brakeman -q` and summarize. Run `bundle exec bundle-audit check` if it is available.
- Negative tests exist for: garbage, expired, and post-logout tokens; wrong password; unknown email; reused reset token; cross-tenant access.

## Output
List findings by severity (Critical, High, Medium, Low) as `[SEV] path:line  what / why / suggested fix`. Then state clearly what was **verified by reading**, what was **run**, and what was **not checked**.

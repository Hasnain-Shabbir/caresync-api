# Learning summaries

Short, human-readable summaries of the Rails docs we need while building CareSync. Each file links to its source so you can read the full guide after the build.

**How to use this list:** go in order, from number 1 to 30. The numbers are the reading order only. The file names are not changed, so links elsewhere keep working. Start with `HANDOFF.md` if you want the current project state first. `helpful-commands.md` is a cheat sheet to keep open while you work.

## Part A: Rails basics

| # | Topic | File |
|---|---|---|
| 1 | Routing | [routing.md](routing.md) |
| 2 | Active Record Validations | [active-record-validations.md](active-record-validations.md) |
| 3 | Migrations, associations, DB constraints | [models-migrations-associations.md](models-migrations-associations.md) |
| 4 | Strong parameters and create | [strong-parameters-and-create.md](strong-parameters-and-create.md) |
| 5 | update, destroy and before_action | [update-destroy-before-action.md](update-destroy-before-action.md) |
| 6 | Error handling with rescue_from | [rescue-from-error-handling.md](rescue-from-error-handling.md) |
| 7 | Testing with Minitest | [testing-minitest.md](testing-minitest.md) |
| 8 | Walkthrough 01: domain models and 409 handler (study guide) | [walkthrough-01-domain-models.md](walkthrough-01-domain-models.md) |

## Part B: GraphQL

| # | Topic | File |
|---|---|---|
| 9 | Guide 02: GraphQL foundation (why, steps, tests) | [guide-02-graphql-foundation.md](guide-02-graphql-foundation.md) |
| 10 | Guide 03: GraphQL mutations and errors-as-data | [guide-03-graphql-mutations.md](guide-03-graphql-mutations.md) |
| 11 | Dev tool: GraphQL sandbox and Postman (setup, usage, troubleshooting) | [guide-dev-tools-graphql-sandbox.md](guide-dev-tools-graphql-sandbox.md) |
| 12 | Guide 04: Patients and the N+1 problem (dataloader) | [guide-04-patients-and-n-plus-one.md](guide-04-patients-and-n-plus-one.md) |
| 13 | Checklist: adding a CRUD resource to the GraphQL API (type, queries, mutations, registration, errors, tests) | [guide-adding-a-crud-resource.md](guide-adding-a-crud-resource.md) |

## Part C: Security, tenancy and API features

| # | Topic | File |
|---|---|---|
| 14 | Guide 05: Authentication with Devise and devise-jwt (login, logout, lockable, allowlist, default-deny) | [guide-05-authentication-devise.md](guide-05-authentication-devise.md) |
| 15 | Guide 06: Multi-tenancy (scope everything to the user's organization, cross-tenant tests) | [guide-06-multi-tenancy.md](guide-06-multi-tenancy.md) |
| 16 | Comparison: authorization with custom policy classes vs Pundit (and the recommendation) | [comparison-authorization-custom-vs-pundit.md](comparison-authorization-custom-vs-pundit.md) |
| 17 | Guide 07: Roles and policies (Pundit, permission matrix, default-deny, field-level rules) | [guide-07-roles-and-policies.md](guide-07-roles-and-policies.md) |
| 18 | Guide 08: Password reset (Devise recoverable, background mailer, requestPasswordReset and resetPassword) | [guide-08-password-reset.md](guide-08-password-reset.md) |
| 19 | Guide 09: Hardening (log redaction, depth and complexity limits, introspection, rack-attack throttling, CORS) | [guide-09-hardening.md](guide-09-hardening.md) |
| 20 | Guide 10: Pagination, sorting and search (Relay connections, sort enum, ILIKE search, page limits) | [guide-10-pagination-sorting-search.md](guide-10-pagination-sorting-search.md) |
| 21 | Guide 10b: Sandbox testing for pagination | [guide-10b-sandbox-testing-pagination.md](guide-10b-sandbox-testing-pagination.md) |
| 22 | Notes: GraphQL type cycles and query limits | [notes-graphql-cycles-and-query-limits.md](notes-graphql-cycles-and-query-limits.md) |
| 23 | **Manual test pack: test data plus a step-by-step check of the whole API** | [testing-the-whole-api.md](testing-the-whole-api.md) |

## Part D: Next level and the SaaS template

| # | Topic | File |
|---|---|---|
| 24 | **Learning plan: next level (database design, ActiveRecord, complex queries, production Rails, GraphQL), with the course outline mapped to Rails** | [learning-plan-production-rails.md](learning-plan-production-rails.md) |
| 25 | **Audit of the company project (functionRX-api): what it does well, gaps and risks, and learning tracks J to O to build in CareSync** | [audit-functionrx-api.md](audit-functionrx-api.md) |
| 26 | **Playbook: from Figma and a scope doc to an ERD, a decision log and a team plan (questions, patterns, review checklist, AKU example)** | [playbook-new-saas-project.md](playbook-new-saas-project.md) |
| 27 | **SaaS template plan: what exists in saas-setup and saas-api, module inventory, decision list, ERD v0 and the build plan** | [saas-template-plan.md](saas-template-plan.md) |
| 28 | **SaaS template API: the contract derived from the saas-setup frontend (27 operations), scope, stack choices, ERD exercise and the T01 to T10 start plan** | [saas-template-contract-and-start.md](saas-template-contract-and-start.md) |
| 29 | **Standards and Claude setup for the SaaS backend: what bliv, functionRX and AKU teach, security findings, folder structure, 16 draft Claude rules, skills (external and our own). For your review** | [saas-backend-standards-and-claude-setup.md](saas-backend-standards-and-claude-setup.md) |
| 30 | Later: custom token authentication (bcrypt, own token table, idle timeout), to learn after the Devise version | [guide-later-custom-token-authentication.md](guide-later-custom-token-authentication.md) |

## Reference (not numbered, use any time)

| Topic | File |
|---|---|
| **Helpful commands cheat sheet (server, tests, database, routes, GraphQL, logs, git)** | [helpful-commands.md](helpful-commands.md) |
| Handoff for a new chat: state, rules, remaining plan | [HANDOFF.md](HANDOFF.md) |

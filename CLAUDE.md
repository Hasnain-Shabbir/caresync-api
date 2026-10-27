# CareSync API

A multi-tenant, HIPAA-style GraphQL API. Rails 8.1 (API only), Ruby 3.4.2, PostgreSQL, Minitest, Pundit, Devise with devise-jwt (allowlist revocation), Solid Queue, rack-attack, rack-cors.

Detailed project rules live in `.claude/rules/*.md` and load automatically. Rules with a `paths:` header load only when matching files are in play. Read the rule for the area you are about to change.

## Where things are
- GraphQL: `POST /graphql`, code in `app/graphql/`. Policies in `app/policies/`. Tests in `test/`.
- Learning guides, project state, and the plan: `learning/` (committed). Start with `learning/HANDOFF.md` and `learning/README.md`.
- Standards and rules rationale: `learning/saas-backend-standards-and-claude-setup.md`.

## Skills (`.claude/skills/`)
Loaded on demand. Only each skill's short description is always in context, and the body loads when it is used. Skills marked manual run only when you type `/name`.
- Automatic by file path: `graphql-operation`, `write-tests`, `db-migration-review` (review only), `security-review-backend` (review only), `graphql-schema` and `postgresql-table-design` (vendored third party).
- Manual: `/domain-feature-slice`, `/erd-design-review` (review only), `/webhook-integration`.
- **Project rules in `.claude/rules/` override vendored skills** when they differ (for example integer-cents money, string enums with `CHECK`). Sources and patches of vendored skills are in `.claude/skills-sources.json`.

## Commands
```
bin/rails test           # whole suite
bin/rubocop              # style
bin/brakeman -q          # security scan
bin/rails server -p 4000 # dev server (Apollo Sandbox at /sandbox in development)
```

## Most important rules (details in `.claude/rules/`)
- The owner types the code. Claude guides and reviews. No extra changes. No migrations unless asked.
- Never read secrets or `.env` files. Never put secrets or personal data in logs.
- Default deny: login required, policies for every operation, tenancy through `current_organization`.
- Never return `exception.message` to a client. Never decode a JWT without verification.
- Commit only when asked, stage by path, `type: message`, no `Co-Authored-By`.

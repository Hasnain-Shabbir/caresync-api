# Learning Notes

Goal: become a proficient Rails backend engineer by building CareSync, a HIPAA-style multi-tenant SaaS API. Background: Node.js/Express, REST and GraphQL. See [ROADMAP.md](ROADMAP.md) for the phased plan.

## Status
- Phase 1 in progress (project foundation).
- Done: `rails new caresync-api --api -d postgresql` (Rails 8.1.4, Ruby 3.4.2, Postgres 16 via Homebrew).
- Done: `bin/rails db:create` made `caresync_api_development` and `caresync_api_test`.
- Next: boot the server and check `/up`, read the generated files, then build the first endpoint (`Organization` model + `Api::V1::Organizations#index`).

## Working style
Short concept explainer with an Express comparison, then I write the code and the assistant reviews and asks "why". No long tutorials.

## Takeaways
- `bin/rails` is a wrapper that runs the app's own Rails version. `db:create` is a Rake task (like an npm script) that reads `config/database.yml` and runs `CREATE DATABASE` for development and test.
- Two databases: development holds working data, test is wiped and rebuilt by the test suite so tests never destroy dev data.
- Inspect a DB: `psql -l`, `bin/rails dbconsole` (add `-e test`), or `bin/rails console` with `Model.count`. In psql: `\dt`, `\d table`, `\c db`, `\q`.

## Ruby drills
- `&:even?` is shorthand for `{ |n| n.even? }`. Practice `select`, `map`, `group_by`, `join` in `irb`.

## Open questions
- After `db:migrate`, does the test DB get the `organizations` table? Why or why not?

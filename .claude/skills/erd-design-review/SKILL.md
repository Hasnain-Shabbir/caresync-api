---
name: erd-design-review
description: Review-only check of an ERD or schema design draft against constraints, tenancy, lifecycle, and the screens it must serve. Run manually with /erd-design-review.
disable-model-invocation: true
disallowed-tools: Edit Write
---

# Review an ERD or schema design (report only, never edit)

Also open `postgresql-table-design` for column types and indexes. Background: `learning/playbook-new-saas-project.md`. Report findings; do not change files.

## Checklist
- [ ] Every table has a primary key and timestamps.
- [ ] Every tenant table has the organization column. Cross-tenant links are blocked by a composite foreign key, not only by Ruby.
- [ ] Every foreign key has an explicit `ON DELETE` and an index.
- [ ] Every business rule is a constraint (`NOT NULL`, `UNIQUE`, `CHECK`), or the reason it is not is written down.
- [ ] Every status or role column is a string with a `CHECK`, and the state machine (states, transitions, who may move them) is written.
- [ ] Many-to-many links are join tables with their own columns and a unique pair.
- [ ] Money, time, and ids follow the written decisions (integer cents, time with zone, id type).
- [ ] Sensitive fields are marked with encryption, audit, and visibility decisions.
- [ ] Deletion and retention are decided for every table.
- [ ] Every screen passes the "one query and an index" test.
- [ ] Break test: a second tenant, a deleted user, 100 times the data, a duplicate webhook, two people editing at once. What breaks?

## Output
Findings by severity with the table and column named, then the questions the owner must answer. Say what you checked from the draft only, and what you could not know (intent, volume).

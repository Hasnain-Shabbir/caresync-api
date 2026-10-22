---
paths:
  - "app/**"
  - "db/**"
  - "test/**"
---

# Architecture: layers and who may call whom

```
GraphQL (types, mutations)          thin: parse input, authenticate, authorize, call a service, shape output
        |
Application services                one use case each: business rules, transaction, returns a Result
        |
Models + query objects + policies   data rules | read, filter, search | who may do what
        |
PostgreSQL                          constraints are the last line of defence
```

Jobs and mailers call services. Nothing calls "up" the diagram.

## Rules
- GraphQL classes only parse input, require login, call a policy, call **one** service, and shape the output. No business logic, no multi-step queries, no external calls in them.
- A service owns one use case and its transaction. It returns a `Result` (success with a value, or failure with a stable `code`). It does not build GraphQL errors.
- Models hold data rules (validations, associations, simple scopes). No external calls and no email sending in callbacks.
- Jobs load records by id and call a service. They never contain business rules.
- Tenancy: every query starts from `current_organization`. Never a global `Model.find`.

## Status in CareSync (target versus today)
- **Today:** the mutations in `app/graphql/mutations/` contain their own logic. There is no `app/services/` yet.
- **Target:** new code follows the layers above. Existing mutations move to services in the planned refactor. Do not "half migrate" a mutation: move a whole use case and its tests together.
- The legacy REST controllers in `app/controllers/api/v1/` are unauthenticated and scheduled for removal. Do not extend them. Do not add REST endpoints.
- Decision recorded: plain service objects with a `Result` (not the `interactor` gem). Change this line only after the owner decides otherwise.

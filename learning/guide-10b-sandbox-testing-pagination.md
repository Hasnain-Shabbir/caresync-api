# Guide 10b: Testing `patients` pagination in the GraphQL sandbox

Status: written 2026-10-23. The same scenarios passed in a script against the seeded development database, but **I have not clicked through the sandbox itself**. If a step differs on your screen, trust the screen and tell me.

Tool setup (route, controller, headers panel) is in `guide-dev-tools-graphql-sandbox.md`. This guide only covers what to type and what to expect.

## 0. Prepare

1. Seed (safe to repeat, adds only, never in production): `bin/rails db:seed`
2. Start the server: `bin/rails server`
3. Open `http://localhost:4000/sandbox`
4. Seed data to expect for **Sunrise Clinic**: 57 patients, so 3 pages (25, 25, 7). **Valley Health** has 6 patients (it must never appear in Sunrise results).

Seeded logins (password `password` for all): `admin@sunrise.test`, `provider@sunrise.test`, `nurse@sunrise.test`, `frontdesk@sunrise.test`, `admin@valley.test`.

## 1. Log in and set the header

Operation:
```graphql
mutation Login($input: LoginInput!) {
  login(input: $input) {
    token
    errors { message code }
  }
}
```
Variables:
```json
{ "input": { "email": "admin@sunrise.test", "password": "password" } }
```
Copy the `token`. In the **Headers** panel add:
```
Authorization: Bearer <paste token>
```
Sunrise and Valley are different tenants, so to test tenancy later you log in again as `admin@valley.test` and swap the header.

## 2. Known issue to know about first: complexity

The complexity limit is 200. Today a page of 25 costs a lot, because every field on the page (including `totalCount`, `page` and so on) is multiplied by `perPage`. If a query below returns:

```
Query has complexity of 251, which exceeds max complexity of 200
```
that is **not a paging bug**. It is the open complexity decision. Work around it for now by selecting fewer fields (for example only `patients { id lastName }`), or a smaller `perPage`. Section 9 tests this on purpose.

## 3. Basic page and metadata

```graphql
query Patients($page: Int, $perPage: Int, $orderBy: PatientOrderEnum) {
  patients(page: $page, perPage: $perPage, orderBy: $orderBy) {
    totalCount
    totalPages
    page
    hasNextPage
    hasPreviousPage
    patients { id lastName firstName }
  }
}
```
(Type names `LoginInput` and `PatientOrderEnum` match the schema definition.)

Use these **Variables** one at a time and compare:

| Variables | Expect |
|---|---|
| `{}` | 25 rows, `page` 1, `totalCount` 57, `totalPages` 3, `hasNextPage` true, `hasPreviousPage` false |
| `{ "page": 2 }` | 25 rows, both flags true |
| `{ "page": 3 }` | 7 rows, `hasNextPage` false, `hasPreviousPage` true |
| `{ "page": 4 }` | empty `patients`, no error (decision: empty, not an error) |
| `{ "perPage": 10 }` | 10 rows, `totalPages` 6 |

Check by eye: page 1 and page 2 share no `id`.

## 4. Clamping (the server enforces the limits)

| Variables | Expect |
|---|---|
| `{ "perPage": 1000 }` | `perPage` comes back as 100, 57 rows (may hit complexity, see section 2) |
| `{ "perPage": 0 }` | `perPage` 1, one row |
| `{ "page": -5 }` | `page` 1 |
| `{ "page": 0 }` | `page` 1 |

Add `perPage page` to the selection to read back what the server actually used.

## 5. Sorting

Use `"orderBy": "LAST_NAME_ASC"` and the other values (as a variable string, not in quotes inside the query text if you type it inline).

| `orderBy` | Expect on page 1 |
|---|---|
| `LAST_NAME_ASC` (also the default) | last names in A to Z order, ties by first name |
| `LAST_NAME_DESC` | Z to A |
| `CREATED_AT_ASC` | oldest patient first (not alphabetical) |
| `CREATED_AT_DESC` | newest first |

Tie test (this is what the `id` tiebreaker protects): with `LAST_NAME_ASC`, page through 1, 2 and 3 and write down every `id`. There should be **57 different ids, none repeated, none missing**. "Smith" appears 12 times, so it spans pages.

Invalid value test: `"orderBy": "NAME"` must fail with a validation error and return no data. (Free from the enum: no client text reaches SQL.)

## 6. Tenancy

1. As Sunrise admin: `totalCount` is 57, no `Valley` patients. Valley's "Clark" and the Valley "Smith" rows must not show up.
2. Log in as `admin@valley.test`, replace the header token. `totalCount` is now 6, `totalPages` 1.
3. A Sunrise patient id fetched directly as Valley returns `NOT_FOUND`:
```graphql
query($id: ID!) { patient(id: $id) { firstName } }
```

## 7. Roles (front desk)

Log in as `frontdesk@sunrise.test` and run:
```graphql
{ patients(perPage: 5) { patients { id lastName dateOfBirth } } }
```
Expect: rows come back, `dateOfBirth` is `null` for every row. Then log in as `admin@sunrise.test` and confirm dates appear.

## 8. Not logged in

Remove the `Authorization` header and run any query above. Expect a top-level error with `extensions.code` of `UNAUTHENTICATED` and no data.

## 9. Complexity (on purpose)

```graphql
{ patients(perPage: 100) { totalCount patients { id } } }
```
Today this is rejected with a complexity message. Write down the number in the message. Then try `perPage: 25` with only `patients { id }`. This is the evidence for the open decision (charge less per row, raise the limit, or lower the max page size).

## 10. Check the SQL (optional but worth doing once)

Tail the log while you run page 2: `tail -f log/development.log`. For one request you should see:
- one `COUNT(*)` for `totalCount`,
- one `SELECT ... ORDER BY ... , "patients"."id" ASC LIMIT 25 OFFSET 25`,
- both filtered by `organization_id`.

Anything more per page (a query per patient) is an N+1 and must be reported.

## 11. Record the result

Write a pass or fail next to each row of the tables in sections 3 to 8 and send me the failures with the exact variables and response. Anything that surprised you also goes in your takeaway in guide 10, section 8.

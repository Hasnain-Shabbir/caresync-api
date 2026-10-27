# Guide 10: Pagination, sorting and search for `patients`

Status: written 2026-10-22, **changed the same day from cursor to page-number pagination** (the frontend has numbered pages: 1, 2, 3 ... 10). **Nothing here has been run or verified yet.** Code samples are a starting point; check them against graphql 2.6.12 as you type.

Method: try first, read second, then write a short takeaway at the bottom.

## 1. Why

Today `patients` returns every row. Two problems:
- A big clinic means a huge response, and a huge PHI dump in one request.
- A frontend table needs pages, sorting and a search box.

Express comparison: this is `?page=&perPage=&sort=&q=` on a REST list, but typed, and with the allowed values written into the schema.

### Why page numbers, not cursors
- The UI shows numbered pages and lets the user jump to page 7. A cursor only means "continue after here", so it cannot jump, and it cannot give a page count.
- Offset paging (`LIMIT per_page OFFSET (page-1)*per_page`) can do both, with `totalCount` and `totalPages`.
- Cost: if rows are added or deleted while someone clicks through, a row can repeat or vanish between pages. Acceptable for a staff table. A cursor connection is the better fit for infinite scroll; add one later only if needed. Do not build both now.
- Large offsets get slower on huge tables. Not a concern at clinic scale. Note it for later.

### Why an enum for sorting
- A free string like `orderBy: "last_name; DROP..."` is an injection risk.
- An enum is an allowlist: the client can only send values you listed. It is also self-documenting in the schema.

### Why a tiebreaker
Many patients share a last name. If the sort is not unique, the database may return tied rows in a different order on each request, so a row can appear on two pages or on none. Always end the order with `id`.

### Why escape `%` and `_`
`ILIKE 'sm%'` treats `%` and `_` as wildcards. If the user types `%`, they match everything. Escape them (`sanitize_sql_like`). Values are still bound parameters, so this is about behavior, not injection.

## 2. Decisions to confirm before you type (no-assumptions rule)

These change what clients see, so they are yours to decide. My recommendation is first.

1. **Search match:** prefix (`smi%`) on first or last name, as the roadmap says. Alternative: contains (`%smi%`), which is friendlier but cannot use a normal index. Recommendation: prefix.
2. **Search scope:** first name, last name, and "first last" together? Recommendation: first and last name only for now. Date of birth must **not** be searchable by front desk, because the field is hidden from them (searching it would leak the value).
3. **`organization.patients`** (the nested list on `OrganizationType`) is also unpaginated. Convert it to the same page type too (breaking change for clients), or leave it and note the gap? Recommendation: leave it for now, flag it, decide when the frontend needs it.
4. **Page sizes:** default 25, max 100 (from the roadmap).
5. **Page type:** a plain `Types::PatientPageType` (recommendation: decided, simple). A generic factory (`PageType.for(item_type)` with `Class.new` and a cache) is over-engineering for one list. Extract it when a second paginated list needs the same fields; the refactor is small because the fields are identical.
6. **Page past the end** (for example `page: 99` of 10): return empty `patients` (recommendation, simple for the frontend) or an error?
7. **`totalCount`:** costs one `COUNT(*)` per request. Fine at this size. OK?

## 3. Steps

Todo list:
1. Sort enum.
2. Page type.
3. `patients` field with `page`, `perPage`, `orderBy`, `search`.
4. Search.
5. Indexes (migration, only when you ask me to run it).
6. Tests.
7. Rules and docs.

### 3.1 Sort enum: `app/graphql/types/patient_order_enum.rb`
- A `Types::BaseEnum` named `PatientOrder` with values such as `LAST_NAME_ASC`, `LAST_NAME_DESC`, `CREATED_AT_ASC`, `CREATED_AT_DESC`.
- Give each value a Ruby `value:` (for example a symbol or a small hash) so the resolver never builds SQL from client text.
- Default order when the argument is missing: `LAST_NAME_ASC` (same as today).
- File name and class name mirror each other (Zeitwerk): `patient_order_enum.rb` defines `Types::PatientOrderEnum < Types::BaseEnum`.
- Code:

```ruby
# frozen_string_literal: true

module Types
  class PatientOrderEnum < Types::BaseEnum
    description "Allowed sort orders for the patients list"

    value "LAST_NAME_ASC", value: { last_name: :asc, first_name: :asc }
    value "LAST_NAME_DESC", value: { last_name: :desc, first_name: :desc }
    value "CREATED_AT_ASC", value: { created_at: :asc }
    value "CREATED_AT_DESC", value: { created_at: :desc }
  end
end
```
- Check: `bin/rails zeitwerk:check`, and `Types::PatientOrderEnum.values.keys` in the console lists the four names.

### 3.2 Page type: `app/graphql/types/patient_page_type.rb`
- `Types::PatientPageType < Types::BaseObject` with these fields, all `null: false`:
  - `patients` (`[Types::PatientType]`, `hash_key: :nodes` so the generic `Paginator` hash stays the same for every list)
  - `total_count`, `total_pages`, `page`, `per_page` (Integer)
  - `has_next_page`, `has_previous_page` (Boolean)
- The resolver returns a plain hash with those keys (graphql-ruby falls back to hash keys when the object has no matching method; **verify in the console**), not an `ActiveRecord::Relation`.
- `total_pages` is `(total_count / per_page.to_f).ceil`. With zero rows it is 0 (decide and test what the frontend should see).
- Lists keep the `complexity:` multiplier rule (see 3.6).
- Later: when the paging math grows, move it to `app/queries/patients/list_query.rb`, not into a generic GraphQL type.

### 3.3 `patients` field in `QueryType`
- Change `field :patients, [Types::PatientType]` to return the page type.
- Arguments:
  - `page: Integer, default_value: 1`
  - `per_page: Integer, default_value: 25`
  - `order_by: Types::PatientOrderEnum, default_value: ...`
  - `search: String, required: false`
- In the resolver, in this order:
  1. `authorize!(Patient, :index?)`
  2. `scope = current_organization.patients` (tenancy first)
  3. apply search
  4. apply order **plus** `.order(:id)` as the last key
  5. clamp: `page = [page, 1].max`, `per_page = per_page.clamp(1, 100)`
  6. `total = scope.count` (before limit and offset; use `reorder(nil)` or count on the unordered scope if the ORDER BY slows it, check with the console)
  7. `nodes = scope.limit(per_page).offset((page - 1) * per_page)`
  8. return a hash: `patients`, `total_count`, `total_pages`, `page`, `per_page`, `has_next_page` (`page < total_pages`), `has_previous_page` (`page > 1`)
- `order_by` default: the enum's Ruby value for `LAST_NAME_ASC`, for example `default_value: Types::PatientOrderEnum.values["LAST_NAME_ASC"].value`. If graphql-ruby rejects that, use `required: false` and `order_by ||= { last_name: :asc, first_name: :asc }` in the resolver. Check which works.
- Do **not** call `.to_a` on the full scope. Only the limited relation is loaded.
- Unlike a graphql-ruby connection, nothing clamps for you here. The clamp in step 5 is the only protection, so test it.

### 3.4 Search
- In the resolver: `strip`, cap the length (for example 50), ignore if blank, escape with `Patient.sanitize_sql_like(term)`, then `where("first_name ILIKE :t OR last_name ILIKE :t", t: "#{escaped}%")`.
- Tenancy still comes from `current_organization.patients`. Search is applied **after** it.
- Per the folder rules, this will move to `app/queries/patients/list_query.rb` later. For now keep it small in the resolver, or put it in the query object straight away if you prefer (your call).
- `totalCount` and `totalPages` must reflect the **filtered** set. A search that matches 3 patients shows 1 page.

### 3.5 Indexes
- Existing index: `organization_id, last_name, first_name`. It already helps `LAST_NAME_ASC`.
- For `CREATED_AT_*` add `organization_id, created_at`. Sort columns that end in `id` for the tiebreaker may need `id` appended to be fully index-ordered. Check with `EXPLAIN`.
- Prefix `ILIKE` needs `text_pattern_ops` or `pg_trgm` to use an index. Not needed at this size; note it for later.
- **I will not run the migration. Tell me when you want it run.** Review it with `/db-migration-review` before.

### 3.6 Complexity and the existing rule
- The "every list has a multiplier" test in `query_limits_test.rb` checks list fields of objects. The page field is **not** a list (it returns one object), so the test may no longer cover `Query.patients`. Look at how the test selects fields and decide: extend it to cover page fields, or add a second test.
- The cost must grow with `perPage`. A flat cost would let a client ask for 100 rows at the price of 1. Use a complexity proc that reads `args[:per_page]` (clamped to 100), for example `10 * per_page.clamp(1, 100) * child_complexity`... then **verify** that a normal page still fits under `max_complexity(200)`. If it does not, tell me. Do not raise the limit without asking.
- Verify the cost of `patients(perPage: 100) { patients { id } totalCount }` and of `perPage: 25` in the console.

## 4. Tests (you write them, I review)

In `test/graphql/queries/patient_query_test.rb` or a new `patient_list_test.rb`:
1. Page 1 returns `perPage` rows, `hasNextPage: true`, `hasPreviousPage: false`.
2. Page 2 returns the following rows, with no overlap with page 1. Last page: `hasNextPage: false`.
3. `totalCount` and `totalPages` are right (for example 30 patients, `perPage: 25`, gives 2 pages).
4. No `perPage` given: 25 rows. `perPage: 1000`: clamped to 100. `perPage: 0` or negative: clamped to 1. `page: 0` or negative: treated as page 1.
5. Page past the end: empty `patients`, no error (or whichever you chose in decision 6).
6. Sorting: each enum value, and a tie on last name stays stable across pages (no row twice, none missing).
7. Search: prefix match, case-insensitive, `%` and `_` treated literally, blank search ignored, long search capped.
8. Search plus paging: `totalCount` and `totalPages` count only matching rows.
9. Tenancy: another organization's patients never appear and are never counted (extend `tenancy_test.rb`).
10. Permission: front desk can list but `dateOfBirth` is still hidden; searching does not reveal it.
11. Query count stays constant for 1 page of 5 vs 25 patients (N+1). The N+1 test is `test/graphql/*`; find it with `grep -rn "n_plus" test`.
12. Unknown `orderBy` value is rejected by GraphQL validation (free from the enum).
13. Complexity: `perPage: 100` costs more than `perPage: 25`, and a normal page is under the limit.

Run: `bin/rails test`, then `bin/rubocop`, then `bin/brakeman -q`. Mark here when done: not run yet.

## 5. Frontend contract (for whoever builds the table)
- Query: `patients(page, perPage, orderBy, search) { patients { ... } totalCount totalPages page perPage hasNextPage hasPreviousPage }`.
- Keep `page`, `search` and sort in the URL. Reset to page 1 when search or sort changes.
- Build the page links from `totalPages` (1, a window around the current page, `...`, last page).
- Key the client cache on `(page, perPage, orderBy, search)` and keep the previous page on screen while the next one loads.

## 6. Update the rules after it works
- `.claude/rules/graphql-operations.md`, "Status in CareSync": remove the "no pagination" line and document the pattern (page type + enum + `id` tiebreaker + clamped `perPage` + complexity from `perPage`) for new lists.
- `learning/HANDOFF.md`: Phase A done, test count.

## 7. Self-check (answers below)
1. Why can a cursor not give numbered pages?
2. Why does a non-unique sort break paging?
3. Why is an enum safer than a string for `orderBy`?
4. What happens to `perPage: 500` here, and who enforces it?
5. Why must `.to_a` not be called on the full scope in the resolver?
6. Why can search on date of birth leak data to front desk?
7. Where does tenancy get applied, and why before search?
8. Why must the page field's complexity depend on `perPage`?

Answers:
1. A cursor only says "continue after this row". It has no position number and no total, so the client cannot jump to page 7 or know there are 10 pages.
2. Two rows with the same sort key have no fixed order, so the database can return them in a different order per request. A row may show on two pages or none. `id` makes the order total.
3. The client can only pick listed values, and the resolver maps them to fixed columns. No client text reaches SQL.
4. Your resolver clamps it to 100. Nothing else does, because this is not a graphql-ruby connection (verify in your test).
5. It loads all rows into memory before `LIMIT` is applied, which defeats pagination.
6. A search result confirms a value even if the field is hidden in the response.
7. At the start (`current_organization.patients`), so every later filter can only narrow rows inside the tenant. The count also stays inside the tenant.
8. Otherwise a client pays the same price for 1 row or 100, and the complexity limit stops protecting the server.

## 8. Your takeaway (write 3 lines in your own words)
-

# Notes: GraphQL query cycles, query limits, and how other projects do it

Status: written 2026-10-23. The comparison with the bliv and AKU repos is from reading their code. The links came from web search results. I did not open every page in full, so treat the summaries below as pointers, not quotes.

## 1. The problem with cycles

A GraphQL schema is a graph, and graphs have cycles: `organization -> patients -> organization -> patients ...`. Each field is legal on its own, but a client can nest them as deep as it wants.

- **Work multiplies.** Each trip around the cycle multiplies the number of rows loaded. Two trips at 25 rows each can mean thousands of rows, from one small request.
- **Cheap to send, expensive to run.** The attacker pays a few hundred bytes. The server pays the database queries and the response size.
- **Not only a DoS issue.** A cycle can also make data reachable by a path nobody thought to authorize (for example a back-reference that skips a permission check).
- **Cycles are not the only shape.** A wide query with no cycle can be just as expensive. A cycle check alone does not make an API safe; bounding the worst-case work of any query does.

## 2. What production APIs do (layers)

1. Every list has a pagination argument and a hard maximum.
2. A cost limit based on the worst-case number of items (GitHub multiplies `first`/`last` down the query and caps the total at 500,000 nodes).
3. A depth limit.
4. Rate limiting by cost, not only by request count.
5. Database timeouts and batching (dataloader).
6. For a first-party frontend: persisted queries (a server-side allow-list of queries).

## 3. How the other projects here handle it (read from their code)

| | CareSync (this repo) | bliv-platform-backend | AKU-app |
|---|---|---|---|
| Pagination | page/perPage, enforced max 30 | page/limit with Kaminari, `graphql-pagination` gem's `collection_type`, **no max on `limit`** (as far as I could see) | Kaminari `page`/`per`, page metadata type |
| `max_depth` | 8 | not set | not set |
| `max_complexity` | 200 | not set | not set |
| `max_query_string_tokens` | 5000 | 5000 | not set |
| Nested lists | one unpaginated one, to be removed | many unpaginated nested lists on `PatientType` | not checked |
| Errors | stable codes, no `exception.message` | `rescue => e` then returns `e.message` to the client | not checked |

So bliv and AKU have no depth or complexity limit, and a client can ask for any `limit`. CareSync's guard rails are stricter. The count/next/prev shape you saw in those projects is the same idea as our page type.

## 4. Resources

- OWASP GraphQL Cheat Sheet: https://cheatsheetseries.owasp.org/cheatsheets/GraphQL_Cheat_Sheet.html (limits on depth and amount, pagination, timeouts, query cost analysis)
- GitHub GraphQL resource limitations (node limit, `first`/`last` required, 1 to 100): https://docs.github.com/en/graphql/overview/rate-limits-and-node-limits-for-the-graphql-api
- Escape, GraphQL query cost analysis: https://escape.tech/blog/graphql-query-cost-analysis/
- Escape, depth limit and cyclic schemas: https://docs.escape.tech/testing/vulnerabilities/resource_limitation/graphql_depth_limit
- Checkmarx, exploiting GraphQL query depth: https://checkmarx.com/blog/exploiting-graphql-query-depth
- graphql-ruby, complexity and depth (not opened by me, standard docs page): https://graphql-ruby.org/queries/complexity_and_depth.html
- graphql-ruby, query analyzers (not opened by me): https://graphql-ruby.org/queries/analysis.html
- Persisted queries (Apollo, not opened by me): https://www.apollographql.com/docs/graphos/routing/security/persisted-queries . Note: graphql-ruby's own persisted-query store (OperationStore) is part of GraphQL-Pro, a paid product. Check licensing before relying on it.

## 5. Decision for CareSync (pending your confirmation)
- Remove `Organization.patients` for now (no unbounded list in the schema).
- Add `Organization.patientsCount` (batched) for counts.
- Add a test that fails when a list field has no pagination and no justified exemption.
- Add `statement_timeout`.
- Record persisted queries as a decision for when the frontend exists.

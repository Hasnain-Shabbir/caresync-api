# Guide 02: GraphQL foundation

Roadmap step 2 of [GRAPHQL-ROADMAP.md](../GRAPHQL-ROADMAP.md). You implement it. This guide explains **why** first, then **what to type**.
Sources: [graphql-ruby Getting Started](https://graphql-ruby.org/getting_started), [Schema](https://graphql-ruby.org/schema/definition), [Objects](https://graphql-ruby.org/type_definitions/objects), [Error handling](https://graphql-ruby.org/errors/overview).

Goal of this step: `POST /graphql` answers queries for organizations and their patients, with tests.

---

## 1. Why GraphQL, and how it differs from the REST you built

| REST (what you built) | GraphQL |
|---|---|
| Many URLs: `/api/v1/organizations`, `/:id` | **One URL**: `POST /graphql` |
| The server decides the response shape | The **client** asks for exactly the fields it wants |
| Needs several round trips for related data | One request can fetch an organization **and** its patients |
| HTTP status codes show errors (404, 422) | Always HTTP 200. Errors live in an `errors` array in the body |
| Routes map to controller actions | A **schema** describes types and fields. Fields map to Ruby methods |

You already know this from GraphQL in Node. The Rails-specific part is how graphql-ruby expresses it.

## 2. Mental map: Apollo (Node) to graphql-ruby

| Apollo / graphql-js | graphql-ruby |
|---|---|
| `typeDefs` written in SDL | **Code-first**: a Ruby class per type, fields declared in code |
| `resolvers: { Query: { organizations } }` | A **method** with the same name as the field, on the type class |
| `context` | A hash you pass to `Schema.execute(..., context: {})`, available as `context` in resolvers |
| `GraphQLError` | `GraphQL::ExecutionError` |
| DataLoader | `GraphQL::Dataloader` (built in, step 4) |
| Apollo Server | You call `CaresyncApiSchema.execute` from one controller action |

## 3. How a request flows

```
POST /graphql  { "query": "{ organizations { name } }", "variables": {} }
  -> GraphqlController#execute        (parses params, builds context)
  -> CaresyncApiSchema.execute        (parse, validate, run)
  -> Types::QueryType#organizations   (your resolver method)
  -> Types::OrganizationType          (picks the requested fields from each Organization)
  -> JSON { "data": { ... } } or { "errors": [ ... ] }
```
Why one controller action? GraphQL has one entry point. All routing happens **inside** the query.

---

## 4. Step by step

### 4.1 Install the gem

```bash
bundle add graphql
```
Why: adds `graphql` to the `Gemfile` and `Gemfile.lock`. It's the only dependency we need for this step.

### 4.2 Run the generator

```bash
bin/rails generate graphql:install
```
Read the output. It creates:

| File | Purpose |
|---|---|
| `app/graphql/caresync_api_schema.rb` | The schema: root query/mutation, limits, error handling |
| `app/graphql/types/query_type.rb` | Entry points for reads (`organizations`, ...) |
| `app/graphql/types/mutation_type.rb` | Entry points for writes (step 3) |
| `app/graphql/types/base_*.rb` | Base classes for your types (a place for shared behaviour) |
| `app/graphql/mutations/base_mutation.rb` | Base class for mutations |
| `app/graphql/resolvers/base_resolver.rb` | Optional reusable resolver base |
| `app/controllers/graphql_controller.rb` | The `/graphql` endpoint |
| route `post "/graphql"` | in `config/routes.rb` |
| edits to `config/application.rb` | SQL **query log tags** (shows which GraphQL field caused each SQL query, useful for N+1 in step 4) |

It also skips GraphiQL because the app is API-only.

### 4.3 Trim what we don't need yet

The generator adds Relay features (global object ids, a `Node` interface). We aren't using them, and unused interface code can raise errors later:

1. Delete `app/graphql/types/node_type.rb`.
2. In `query_type.rb`, delete the `node`, `nodes` and `test_field` fields and their methods.
3. In `caresync_api_schema.rb`, delete the `resolve_type`, `id_from_object` and `object_from_id` methods.
4. Keep `mutation_type.rb` as it is (its `test_field` stays until step 3, because a mutation type needs at least one field).
5. In `config/routes.rb`, keep one `post "/graphql", to: "graphql#execute"` line. Delete the stale commented-out lines.

Why trim: smaller surface area, nothing in the schema you can't explain.

### 4.4 Define the types

One class per file, in `app/graphql/types/`.

`patient_type.rb`
```ruby
module Types
  class PatientType < Types::BaseObject
    field :id, ID, null: false
    field :first_name, String, null: false
    field :last_name, String, null: false
    field :date_of_birth, GraphQL::Types::ISO8601Date, null: false
  end
end
```

`organization_type.rb`
```ruby
module Types
  class OrganizationType < Types::BaseObject
    field :id, ID, null: false
    field :name, String, null: false
    field :patients, [ Types::PatientType ], null: false
  end
end
```

Why each piece:
- `field :first_name` is exposed as `firstName` in GraphQL. graphql-ruby camelizes automatically.
- With no method defined, a field calls the method of the same name on the **object** (the `Organization` or `Patient` record). `field :name` calls `organization.name`. That's the default resolver.
- `null: false` means "this field is never null". If it returns nil, the whole parent becomes null and an error is raised. Use it only when the DB guarantees the value (`null: false` columns).
- `ID` is serialized as a **string**, so clients see `"1"`, not `1`. Remember this in tests.
- `ISO8601Date` serializes to `"1990-04-12"`.
- `patients` calls `organization.patients`, which loads every patient with one extra query per organization. That's the N+1 problem we fix in step 4. We accept it now so you can see it later.

**HIPAA note:** `PatientType` exposes PHI. For now the API has no auth, and the data is test fixtures only. This must not be deployed before steps 5 to 7.

### 4.5 Define the queries

In `app/graphql/types/query_type.rb`:

```ruby
module Types
  class QueryType < Types::BaseObject
    field :organizations, [ Types::OrganizationType ], null: false

    def organizations
      Organization.order(:name)
    end

    field :organization, Types::OrganizationType, null: true do
      argument :id, ID, required: true
    end

    def organization(id:)
      Organization.find(id)
    end
  end
end
```

Why:
- `field :organizations` plus `def organizations`: the field name and method name match, and that method is the resolver.
- `Organization.order(:name)` returns a relation. graphql-ruby loads it when it needs the records.
- `argument :id, ID, required: true` becomes `organization(id: "1")`. Resolver methods receive arguments as keyword arguments (`id:`).
- `organization` is `null: true` so a missing record can return `null` for that field, plus an error, instead of failing the whole response.

### 4.6 Turn "not found" into a GraphQL error

`Organization.find` raises `ActiveRecord::RecordNotFound`. Without handling, the whole request raises. In `caresync_api_schema.rb`, inside the class:

```ruby
rescue_from(ActiveRecord::RecordNotFound) do |_err, _obj, _args, _ctx, field|
  raise GraphQL::ExecutionError.new(
    "#{field.type.unwrap.graphql_name} not found",
    extensions: { code: "NOT_FOUND" }
  )
end
```

Why:
- `rescue_from` in the schema is the GraphQL version of `rescue_from` in your REST `ApplicationController`.
- `GraphQL::ExecutionError` is the supported way to return an error for one field. The response gets `data: { organization: null }` and an `errors` entry.
- `extensions: { code: "NOT_FOUND" }` gives clients a **stable machine-readable code**. Clients should switch on `code`, never parse `message`.
- `field.type.unwrap.graphql_name` gives `"Organization"` for the message.

### 4.7 Check the controller (no code, just read)

Open `app/controllers/graphql_controller.rb`. Understand:
- `prepare_variables` accepts variables as a JSON string, a hash, or nothing.
- `context = {}` is where `current_user` goes in step 5.
- `render json: result` always returns HTTP 200.
- In development, unexpected exceptions return a 500 with a backtrace. In other environments they're raised normally.

It inherits from your `ApplicationController`, so the REST `rescue_from` handlers apply too. They only catch exceptions that escape the schema.

---

## 5. Tests to write

Two levels, like the REST API had.

### 5.1 Schema tests (fast, no HTTP): `test/graphql/queries/organizations_query_test.rb`

A helper:
```ruby
def execute(query, variables: {})
  CaresyncApiSchema.execute(query, variables: variables, context: {}).to_h
end
```
Tests to write:
1. `organizations` returns both fixtures ordered by name (`Sunrise Clinic`, `Valley Health`).
2. `organization(id:)` returns one record. Pass the id as a **string** (`org.id.to_s`).
3. An unknown id (`"0"`) gives `data.organization == nil`, and an error with message `"Organization not found"` and `extensions.code == "NOT_FOUND"`.
4. `organization { patients { firstName lastName dateOfBirth } }` returns Alice and Bob for `sunrise`, and Alice's date of birth is `"1990-04-12"`.
5. A query for a nonexistent field (`{ organizations { nope } }`) gives no `data` and an error mentioning `doesn't exist`.

### 5.2 Request tests (full stack): `test/controllers/graphql_controller_test.rb`

```ruby
post graphql_url, params: { query: "{ organizations { name } }" }, as: :json
```
Tests to write:
1. A query returns JSON with the organization names.
2. Variables are passed through (`variables: { id: org.id.to_s }`).
3. An invalid query still returns HTTP 200 with an `errors` array (`assert_response :success`, then check `parsed_body["errors"]`).

Why both levels: schema tests are fast and focused on resolvers. Request tests prove the controller, params and JSON parsing work.

---

## 6. Verify

```bash
bin/rails test
bin/rubocop
bin/brakeman -q
bin/rails routes -g graphql          # graphql  POST  /graphql  graphql#execute
curl -s localhost:4000/graphql -H 'Content-Type: application/json' \
  -d '{"query":"{ organizations { id name } }"}'
```
The dev DB may be empty, so create rows in `bin/rails console` first if you want to see data. Then commit, for example: `feat: add GraphQL endpoint with organization queries`.

---

## 7. Self-check (answers at the bottom)

1. Why is there only one route for GraphQL?
2. A client asks for `{ organizations { name } }`. Does the response include `id` or `patients`? Why?
3. Why can `field :name` work without a `def name` method?
4. Why does a not-found `organization(id:)` still return HTTP 200?
5. Why `null: true` on the `organization` query but `null: false` on `name`?
6. Why do tests pass the id as `"1"` and not `1`?
7. Why is exposing `patients` risky now, and what steps fix it?

**Answers:**
1. All operations are inside the query body. The URL doesn't pick an operation, the schema does.
2. No. GraphQL returns only the requested fields, which is the main benefit over REST.
3. The default resolver calls the same-named method on the underlying object (`organization.name`).
4. GraphQL separates transport success from field errors. The request was processed. The failure is reported per field in `errors`.
5. A missing record is expected, so the field must be able to be null. `name` is a NOT NULL column, so null would be a bug.
6. The `ID` scalar is always a string in GraphQL, even if the DB id is an integer.
7. It's unauthenticated PHI, and any caller can read any organization's patients. Steps 5 (auth), 6 (tenancy) and 7 (authorization) fix it.

---

## 8. What comes next

Guide 03: **mutations and errors-as-data**: `createOrganization`, `updateOrganization`, `deleteOrganization` with input types and `userErrors`.

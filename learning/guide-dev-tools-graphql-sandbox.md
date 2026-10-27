# Dev tool guide: GraphQL sandbox and Postman

A reusable guide for exploring and testing the GraphQL API by hand. Written so you can repeat it in any Rails GraphQL project.
Sources: [Apollo Embeddable Sandbox](https://www.apollographql.com/docs/graphos/platform/sandbox#embedding-sandbox), [graphql-ruby: GraphiQL](https://graphql-ruby.org/getting_started), Rails `ActionController::API`.

Not run end to end by me. If the page doesn't load, check section 6.

---

## 1. Why you want a sandbox

In Node you open Apollo Sandbox, write a query, and see the schema and docs on the side. Postman works, but a sandbox gives you:
- the **schema explorer** (every query and mutation, with arguments and types)
- **autocomplete** and **inline errors** while typing
- **variables and headers** panels (where the auth token goes in step 5)
- a **history** of past operations

A sandbox is the fastest way to learn a schema you didn't write, which is most of the job.

## 2. Options, and why we picked one

| Option | How | Cost | Verdict |
|---|---|---|---|
| **Embedded Apollo Sandbox** (we use this) | A dev-only page in your app loads Apollo's script from a CDN | A route, a controller, no gems | Simplest. Same origin as the API, so no CORS |
| Hosted Apollo Sandbox | Open `studio.apollographql.com/sandbox/explorer`, paste your URL | Needs CORS on the Rails side (`rack-cors`) | Fine, but extra setup |
| `graphiql-rails` gem | GraphiQL mounted at `/graphiql` | Needs the asset pipeline (Sprockets), which API-only apps don't have | Skip for API apps |
| Postman GraphQL request | New, GraphQL, paste URL, refresh schema | None | Good backup, weaker explorer |

## 3. Setup (embedded Apollo Sandbox)

### 3.1 Route
In `config/routes.rb`:
```ruby
get "/sandbox", to: "sandbox#show" if Rails.env.development?
```
Why `if Rails.env.development?`: the route simply **doesn't exist** in production. An open explorer on a PHI API is a data leak, so this is a safety line, not a style choice.

### 3.2 Controller
`app/controllers/sandbox_controller.rb`:
```ruby
class SandboxController < ApplicationController
  def show
    render html: <<~HTML.html_safe
      <!DOCTYPE html>
      <html>
        <body style="margin:0;height:100vh">
          <div id="sandbox" style="width:100%;height:100%"></div>
          <script src="https://embeddable-sandbox.cdn.apollographql.com/_latest/embeddable-sandbox.umd.production.min.js"></script>
          <script>
            new window.EmbeddedSandbox({
              target: "#sandbox",
              initialEndpoint: window.location.origin + "/graphql"
            });
          </script>
        </body>
      </html>
    HTML
  end
end
```

What each part does:
- `render html:` sends a string as `text/html`. It works in `ActionController::API`, so no views or layouts are needed.
- `<<~HTML` is a Ruby **heredoc**: a multi-line string with the leading indentation trimmed.
- `.html_safe` tells Rails not to escape the string. It's safe here because the string is fixed text, with no user input.
- `EmbeddedSandbox` is Apollo's component. `target` is the `div` it fills, and `initialEndpoint` is where it sends queries.
- `window.location.origin + "/graphql"` builds `http://localhost:4000/graphql` from whatever host and port the page is served from.

### 3.3 Open it
Start the server (`bin/rails server`) and go to `http://localhost:4000/sandbox`. You should see the explorer, the editor, and the Variables/Headers panels.

### 3.4 Commit
`chore: add development-only Apollo Sandbox page`

## 4. How to use it

1. **Explorer (left):** click a field to add it to the query. Open `Mutation` to see `createOrganization` and its input.
2. **Operation (middle):** write or edit the query. Errors show with red underlines.
3. **Variables (bottom):** a JSON object for `$input` and `$id`.
4. **Response (right):** the JSON from the server. Check `errors` at the top level and inside the payload.
5. **Headers (bottom):** later, add `Authorization: Bearer <token>` here (step 5).

Example to try:
```graphql
mutation($input: CreateOrganizationInput!) {
  createOrganization(input: $input) {
    organization { id name }
    errors { message path code }
  }
}
```
Variables: `{ "input": { "name": "Sandbox Clinic" } }`

## 5. Security notes (HIPAA mindset)

- The route exists **only in development**. In `bin/rails routes` on production there is no `/sandbox`. Confirm with `RAILS_ENV=production bin/rails routes -g sandbox` (it should print nothing).
- The sandbox uses **introspection** to list your schema. The roadmap's hardening step turns introspection **off in production**, so even a leaked URL shows nothing.
- The page loads a script from Apollo's CDN. That's acceptable on a developer machine with no real PHI. Never use it against production data.
- Before authentication exists (steps 5 to 7), anyone who can reach `/graphql` can read everything. That's why the data is test fixtures and the app isn't deployed.

## 6. Troubleshooting

| Symptom | Likely cause |
|---|---|
| `No route matches [GET] "/sandbox"` | not in development, or the route line is missing. Check `bin/rails routes -g sandbox` |
| `uninitialized constant SandboxController` | the file name or class name doesn't match (`sandbox_controller.rb` and `SandboxController`) |
| Blank page | no internet (the script comes from a CDN), or the browser console shows a blocked script |
| Explorer is empty or says it can't reach the endpoint | the schema fails to load. Run `bin/rails runner "puts CaresyncApiSchema.to_definition"` and read the first error |
| 500 on `/graphql` | read the first line of the error: a file and a line number (see the debugging notes from the mutations work) |
| Mutations missing from the explorer | they aren't registered in `Types::MutationType`, or a class name doesn't match its file name |

## 7. Postman as a backup

`New`, `GraphQL`, enter `http://localhost:4000/graphql`, open the **Schema** tab and refresh. It's a plain HTTP request underneath: `POST /graphql` with `{"query": "...", "variables": {...}}`.

The same call from the terminal:
```bash
curl -s localhost:4000/graphql -H 'Content-Type: application/json' \
  -d '{"query":"{ organizations { id name } }"}'
```

## 8. Self-check

1. Why does the sandbox page not need CORS configuration?
2. Why does the route have `if Rails.env.development?`, and what would be the risk without it?
3. What does `.html_safe` do, and why is it OK here?
4. Where does the auth token go once authentication exists?
5. How do you check that the schema loads, without opening the browser?

**Answers**
1. The page and the API are served from the same origin, so the browser doesn't treat the request as cross-origin.
2. It removes the page in production. Without it, an open explorer on a PHI API would help an attacker read the schema and queries.
3. It stops Rails from escaping the HTML string. It's OK because the string is fixed and contains no user input.
4. In the Headers panel, as `Authorization: Bearer <token>`.
5. `bin/rails runner "puts CaresyncApiSchema.to_definition"`. If it prints the schema, it loads.

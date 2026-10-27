# Error handling in a Rails API (`rescue_from`)

Sources: [ActiveSupport::Rescuable API](https://api.rubyonrails.org/classes/ActiveSupport/Rescuable/ClassMethods.html), [Action Controller Overview](https://guides.rubyonrails.org/action_controller_overview.html) (strong params and 400s), [Rails Guides: Debugging / Error Reporting](https://guides.rubyonrails.org/error_reporting.html). Status names below were checked in this project's `bin/rails runner` (Rails 8.1).

---

## 1. The problem we are solving

Your actions will fail in predictable ways:

| What the client did | What goes wrong in Rails | What the client should get |
|---|---|---|
| `GET /api/v1/organizations/999` (no such id) | `Organization.find(999)` raises `ActiveRecord::RecordNotFound` | `404` and a JSON error |
| `POST` with a duplicate name | `create!` raises `ActiveRecord::RecordInvalid` | `422` and the validation messages |
| `POST` with no `organization` key | `params.expect(...)` raises `ActionController::ParameterMissing` | `400` and a JSON error |

If you do nothing, Rails still returns the right status codes, but the **body** is wrong for an API:
- In development you get an HTML debug page or a big JSON stack trace.
- In production you get an empty or generic body.
- Every error looks different, so a client (React app, mobile app) can't have one piece of code that reads errors.

Goal: **every error from CareSync returns the same JSON shape**, and we write that logic **once**, not in every action.

---

## 2. The mental model (Express comparison)

In Express you handle errors in two parts:
```js
// in a route
app.get('/orgs/:id', async (req, res, next) => {
  const org = await Org.findByPk(req.params.id);
  if (!org) return next(new NotFoundError());   // raise
  res.json(org);
});

// one error middleware at the bottom
app.use((err, req, res, next) => {                // handle, once
  if (err instanceof NotFoundError) return res.status(404).json({ error: ... });
  res.status(500).json({ error: ... });
});
```

Rails does the same two parts:
1. **Raise:** the action (or ActiveRecord) raises an exception, and the action stops there.
2. **Handle once:** a `rescue_from` line in a controller says "when this exception class is raised in any action of mine, run this method instead".

`rescue_from` is the error middleware, except it is matched by **exception class** instead of an `if` chain.

---

## 3. What happens step by step

Request: `GET /api/v1/organizations/999`

```
1. Router matches the route, calls Api::V1::OrganizationsController#show
2. show runs:   org = Organization.find(params[:id])
3. No row with id 999, so ActiveRecord raises ActiveRecord::RecordNotFound
4. show stops immediately (the lines after `find` never run, and no render happens)
5. Rails catches the exception and asks the controller:
      "do you have a rescue_from for RecordNotFound (or a parent class of it)?"
   - It looks in OrganizationsController first, then ApplicationController, then up the chain.
   - YES: it calls your handler method. The handler calls `render json: ..., status: ...`.
          The response goes to the client. Done.
   - NO:  the exception leaves the controller and hits Rails' own error middleware,
          which builds the default 404 (debug page in dev, generic in production).
```

Key point: **after your handler renders, the request is finished normally.** You don't `raise` again and you don't `return` anything special.

---

## 4. Why `find` raises (and how that keeps actions short)

```ruby
Organization.find(5)          # raises RecordNotFound if missing   -> "this MUST exist"
Organization.find_by(id: 5)   # returns nil if missing             -> "maybe it exists"
```

If every action used `find_by`, every action would need:
```ruby
org = Organization.find_by(id: params[:id])
return render(json: { error: ... }, status: :not_found) if org.nil?
```
copied into `show`, `update` and `destroy`. With `find` plus one `rescue_from`, each action only writes the happy path:
```ruby
def show
  org = Organization.find(params[:id])
  render json: org
end
```
Same idea for `create!` and `save!` (the versions with `!` raise, while the versions without it return `false`).

---

## 5. The syntax

```ruby
rescue_from ExceptionClass, with: :method_name
```
- `ExceptionClass`: the class to catch. A subclass of it is also caught (`exception.is_a?(klass)`).
- `with: :method_name`: a symbol naming a method in this controller. If that method takes one argument, Rails passes the exception object (so you can read `e.message`, `e.record`, etc.).
- Instead of `with:` you can pass a block:
```ruby
rescue_from ActiveRecord::RecordNotFound do |exception|
  render json: { error: exception.message }, status: :not_found
end
```
- You can list several classes for the same handler: `rescue_from ErrA, ErrB, with: :handle`.

Official example (from the API docs):
```ruby
class ApplicationController < ActionController::Base
  rescue_from User::NotAuthorized, with: :deny_access
  rescue_from ActiveRecord::RecordInvalid, with: :show_record_errors

  private
    def deny_access
      head :forbidden
    end

    def show_record_errors(exception)
      redirect_back_or_to root_url, alert: exception.record.errors.full_messages.to_sentence
    end
end
```
(That example redirects because it's a full-stack app. Ours renders JSON.)

### Rules worth memorizing
1. **Order matters.** Handlers are searched **from the bottom up** and the first match wins. So put the general ones (`StandardError`) **first** and the specific ones **after**. If a general handler sits at the bottom, it hides all the specific ones above it.
2. **Inheritance.** A `rescue_from` in `ApplicationController` applies to every controller that inherits from it, including `Api::V1::OrganizationsController`.
3. **Exceptions inside a handler are not propagated**, so keep handlers tiny and safe.
4. Handler methods usually go under `private` (they are not routes).

---

## 6. The error envelope (one shape for all errors)

Pick one JSON structure and use it everywhere, so a client can always write `response.error.message`.

```json
{
  "error": {
    "code": "not_found",
    "message": "Organization not found"
  }
}
```
For validation failures, add a `details` field:
```json
{
  "error": {
    "code": "validation_failed",
    "message": "Validation failed",
    "details": { "name": ["has already been taken"] }
  }
}
```
Where does the data come from?
- `RecordNotFound`: `exception.message` (like `Couldn't find Organization with 'id'=999`), or your own text. **Careful with HIPAA later:** exception messages can include record data. Writing your own message is safer.
- `RecordInvalid`: `exception.record.errors` (the model's validation errors; `.to_hash` gives `{ name: ["has already been taken"] }`).
- `ParameterMissing`: `exception.param` is the missing key.

---

## 7. Status codes you need (verified in this app)

Use symbols or numbers, they are the same:

| Symbol | Number | Use for |
|---|---|---|
| `:bad_request` | 400 | request is malformed or missing required params |
| `:not_found` | 404 | record doesn't exist |
| `:unprocessable_content` | 422 | validation failed |
| `:created` | 201 | `create` succeeded |
| `:no_content` | 204 | `destroy` succeeded (no body) |

Warning: the older `:unprocessable_entity` is **not** a valid name in this Rack version here. Use `:unprocessable_content` (or `422`).

Rails already has these defaults for the three exceptions above (checked with `ActionDispatch::ExceptionWrapper.rescue_responses`): `RecordNotFound` is `:not_found`, `ParameterMissing` is `:bad_request`, `RecordInvalid` is `:unprocessable_content`. We keep the same codes and only replace the response **body**.

---

## 8. How this fits CareSync (what you will build)

Right now `app/controllers/application_controller.rb` is:
```ruby
class ApplicationController < ActionController::API
end
```
Every controller you've made inherits from it. That's the right single place to put the handlers.

The plan, in order:

**Step A: the handler for "not found".** In `ApplicationController`:
- add one `rescue_from` line for `ActiveRecord::RecordNotFound`, pointing at a private method;
- write the private method so it renders the envelope (section 6) with status 404.

**Step B: make an action that can raise.** Change `show` in the organizations controller from the placeholder string to a real `Organization.find(params[:id])` followed by a render of the record.

**Step C: prove it with a test**, in `test/controllers/api/v1/organizations_controller_test.rb`:
- a request for an id that exists returns 200;
- a request for an id that does not exist returns 404 **and** the JSON has the keys you chose. Hint: `assert_response :not_found`, then `response.parsed_body` gives you the hash.

**Step D (later, same pattern):** add handlers for `RecordInvalid` (422) and `ParameterMissing` (400) when we build `create` and `update`. One more `rescue_from` line plus one more method each, nothing else changes.

How to check it by hand: `bin/rails server`, then `curl -i localhost:3000/api/v1/organizations/999` and look at the status line and body.

---

## 9. Common mistakes to watch for
- **Forgetting `private`.** A public method in a controller can become an action.
- **Calling `render` twice** (once in the action, once in the handler). Raise **or** render, not both. If the action raised, the handler is the only render.
- **Wrong order** of `rescue_from` lines (see rule 1), where a `StandardError` handler declared last swallows everything.
- **Rescuing `StandardError` too early.** That hides real bugs as "errors". We'll decide on a 500 handler later, once logging is set up.
- **Using an unknown status symbol.** It fails with an error instead of a response. The table in section 7 is checked.

---

## 10. Self-check questions (answer in your own words)
1. After `Organization.find(999)` raises, does the next line in the action run? Why or why not?
2. What happens to the request if no `rescue_from` matches?
3. If you put `rescue_from StandardError` **below** the `RecordNotFound` one, which handler runs for a missing record? What if it is **above**?
4. Why is it better for `show`, `update` and `destroy` to use `find` rather than `find_by`?
5. Why is it risky to put `exception.message` straight into the response for a healthcare app?

## Later phases
- Phase 4: a handler for authorization failures (Pundit's `NotAuthorizedError` becomes 403).
- Phase 5: PHI-safe messages, error tracker scrubbing, audit logging of failures.
- Phase 6: `rescue_from` for rate limits and idempotency conflicts, and OpenAPI documentation of the error shapes.

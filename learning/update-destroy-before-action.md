# `update`, `destroy` and `before_action`

Sources: [Action Controller Overview, Callbacks](https://guides.rubyonrails.org/action_controller_overview.html), [Active Record Basics, Update and Delete](https://guides.rubyonrails.org/active_record_basics.html). Related: [rescue-from-error-handling.md](rescue-from-error-handling.md), [strong-parameters-and-create.md](strong-parameters-and-create.md).

---

## 1. What you are building

| Request | Action | Success response |
|---|---|---|
| `PATCH /api/v1/organizations/:id` | `update` | 200 and the updated record |
| `DELETE /api/v1/organizations/:id` | `destroy` | 204 and **no body** |

Errors come for free from the handlers you already wrote:
- missing id: `find` raises `RecordNotFound`, so 404.
- invalid data on update: `update!` raises `RecordInvalid`, so 422.
- no `organization` key: `params.expect` raises `ParameterMissing`, so 400.

You write no new error code for these two actions.

---

## 2. Updating a record in Active Record

```ruby
book = Book.find(1)
book.update(title: "New title")     # validates, saves, returns true/false
book.update!(title: "New title")    # validates, saves, raises RecordInvalid on failure
```
`update` is a shortcut for "assign the attributes, then `save`". It runs validations first and sets `updated_at` automatically.

### `update` vs `update!`
| | Invalid data | Fits our style? |
|---|---|---|
| `update` | returns `false`, nothing saved, **no exception** | No. You would need `if/else` in every action. |
| `update!` | **raises** `ActiveRecord::RecordInvalid` | Yes. The `rescue_from` renders the 422. |

This is the same reason as `create!` vs `create` in the previous doc.

### Watch out: `update_all`
`Book.update_all(...)` skips validations and callbacks and hits the database directly. Don't use it for normal request handling.

---

## 3. Deleting a record

```ruby
book.destroy     # DELETE for one record. Runs Rails callbacks (before_destroy etc).
book.destroy!    # same, but raises ActiveRecord::RecordNotDestroyed if it couldn't
book.delete      # direct SQL DELETE, skips callbacks and validations
```
- Use **`destroy!`** in controllers. If something prevents deletion (a callback aborts it, or a rule such as "can't delete an organization that has patients"), you get an exception and not a silent `false`.
- `delete` is for special cases only. Skipping callbacks later means skipping things like audit logging.

Note: later, in Phase 2, we will probably use **soft delete** (`discard`) for patient data instead of really deleting rows. Hard deletes of PHI are a bigger decision. For `Organization` in this learning step a plain `destroy!` is fine.

### What does `destroy!` return?
The destroyed record (frozen). You don't render it. For a 204 you send **no body**:
```ruby
head :no_content
```
`head` sends only a status and headers. Use it when there is nothing to put in the body.

---

## 4. The repeated-code problem

`show`, `update` and `destroy` all start with the same line:
```ruby
organization = Organization.find(params[:id])
```
Three copies means three places to change later (for example when we scope by tenant: `Current.organization.organizations.find`...). Rails has a tool for this.

---

## 5. `before_action`

A `before_action` is a method that runs **before** the controller action.

Express comparison: it's route-level middleware.
```js
router.get('/:id', loadOrg, show);       // loadOrg runs first, sets req.org, calls next()
```

Rails form:
```ruby
class WidgetsController < ApplicationController
  before_action :set_widget, only: [:show, :update, :destroy]

  def show
    render json: @widget
  end

  def update
    @widget.update!(widget_params)
    render json: @widget
  end

  private

  def set_widget
    @widget = Widget.find(params[:id])
  end
end
```

How it works, step by step:
1. A request reaches `show`, `update` or `destroy`. Rails runs `set_widget` first.
2. `set_widget` runs `find` and stores the result in `@widget`.
3. Then the action runs. It can use `@widget` directly, with no `find` of its own.
4. For `index` and `create`, the callback is **not** run because of `only:`.

### The pieces
- **`@widget`** (an instance variable, a variable starting with `@`) is shared between all methods of the same controller object during one request. It's how the callback hands the record to the action. A plain local variable (no `@`) would disappear when the callback method ends.
- **`only: [...]`** limits the callback to the listed actions. **`except: [...]`** does the opposite.
- **`private`**: the callback method must be private so it isn't routable.

### What if `find` fails inside the callback?
- `find` raises `RecordNotFound` in the callback. The action never runs.
- `rescue_from` still catches it, as before, because callbacks run in the same request. The 404 comes from the same handler.

### Halting
If a `before_action` calls `render` or `redirect_to`, the chain stops. The action and any later callbacks don't run. (We use this idea later for authentication: "if not logged in, render 401 and stop".)

### Inheritance and skipping
- A `before_action` in `ApplicationController` runs for every controller.
- `skip_before_action :name, only: [...]` exempts specific actions. We'll need that for login/signup in Phase 3.

### Naming convention
`set_<thing>` for loading a record (`set_organization`). Not enforced, but everyone reading Rails expects it.

---

## 6. Test checklist (minitest)
```ruby
patch api_v1_organization_url(org), params: { organization: { name: "Renamed" } }, as: :json
delete api_v1_organization_url(org), as: :json
```
- `org.reload.name` re-reads the row from the database. Use it to prove that the update was saved.
- `assert_response :no_content` and `assert_difference("Organization.count", -1)` for destroy.
- For 204, `response.body` is empty.
- A missing id is `api_v1_organization_url(id: 0)`.

---

## 7. Self-check questions
1. Why is `update!` the better choice than `update` in our controllers?
2. What does `head :no_content` send, and why is there no JSON body on a delete?
3. Why does `set_organization` use `@organization` and not `organization`?
4. If `find` raises inside a `before_action`, does the action run? Who produces the 404?
5. What would `only: [:show, :update, :destroy]` stop from happening for `index` and `create`?
6. What is the difference between `destroy!` and `delete`? Why does it matter for audit logging later?

# Routing (final guide)

Source: [Rails Guides: Rails Routing](https://guides.rubyonrails.org/routing.html)
File you edit: `config/routes.rb`

Contents: 1 What routing does · 2 Request lifecycle · 3 Hand-written routes · 4 `resources` · 5 `namespace` · 6 `scope` · 7 Route helpers · 8 Reading `bin/rails routes` · 9 Extra routes (member/collection) · 10 Nested routes · 11 Order · 12 It's all Ruby methods · 13 Errors · 14 CareSync · 15 Self-check

---

## 1. What routing does

A request arrives as text: `GET /api/v1/organizations`. The router answers two questions:

1. **Which controller class handles it?**
2. **Which method (action) on that class?**

That's all. It doesn't query the DB or build JSON. It's a lookup table.

**Express comparison**

```js
// Express: you pass the handler function directly
app.get('/api/v1/organizations', organizationsController.index)
```
```ruby
# Rails: you pass a string, Rails finds the class by naming convention
get "/api/v1/organizations", to: "api/v1/organizations#index"
```

The string `"api/v1/organizations#index"` is `controller_path#action`:

| Part | Meaning | Becomes |
|---|---|---|
| `api/v1/organizations` | slashes become `::`, `_controller` is added | class `Api::V1::OrganizationsController` |
| same part | file path | `app/controllers/api/v1/organizations_controller.rb` |
| `#index` | the action | method `index` on that class |

There is no `require` or `import`. Autoloading (Zeitwerk) maps a class name to a file path.

## 2. Request lifecycle, end to end

```
GET /api/v1/organizations
  -> middleware (logging, request id, ...)
  -> router (config/routes.rb): picks Api::V1::OrganizationsController#index
  -> controller: before_actions run, then the index method
  -> index loads data via the model, renders JSON
  -> response goes back
```
In `log/development.log` you'll see `Started GET ...`, `Processing by Api::V1::OrganizationsController#index`, SQL lines, then `Completed 200 OK`.

## 3. Hand-written routes

```ruby
get  "organizations",     to: "organizations#index"
get  "organizations/:id", to: "organizations#show"
post "organizations",     to: "organizations#create"
```
`:id` is a **dynamic segment**, like Express `:id`. It lands in `params[:id]` (Express: `req.params.id`) and is always a String.

## 4. `resources`: the shortcut for 95% of routes

Rails convention says every "thing" has the same operations. `resources :organizations` writes them all:

| Verb | Path | Action | What it's for |
|---|---|---|---|
| GET | /organizations | `index` | list all |
| GET | /organizations/:id | `show` | one record |
| POST | /organizations | `create` | create |
| PATCH/PUT | /organizations/:id | `update` | change |
| DELETE | /organizations/:id | `destroy` | delete |
| GET | /organizations/new | `new` | HTML form (**skip in APIs**) |
| GET | /organizations/:id/edit | `edit` | HTML form (**skip in APIs**) |

An API has no HTML forms, so ask for just what you need:

```ruby
resources :organizations, only: :index                      # today
resources :organizations, only: [:index, :show, :create]    # later
resources :organizations, except: [:new, :edit]             # everything but forms
```

The same path with different verbs means different routes (`PATCH` and `DELETE` on `/organizations/42`). PATCH means "change some fields" and PUT means "replace everything". Both map to `update`, and clients mostly send PATCH.

## 5. `namespace`: grouping and versioning

APIs version their URLs (`/api/v1/...`) so `v2` can ship without breaking clients. `namespace` changes **three things at once**:

```ruby
namespace :api do
  namespace :v1 do
    resources :organizations, only: :index
    resources :users, only: :index      # more resources go INSIDE the same v1 block
  end
  namespace :v2 do
    resources :organizations, only: :index   # /api/v2/..., Api::V2::OrganizationsController
  end
end
```

| What changes | Result |
|---|---|
| URL prefix | `/api/v1/organizations` |
| Controller class | `Api::V1::OrganizationsController` |
| File location | `app/controllers/api/v1/organizations_controller.rb` |
| Helper name | `api_v1_organizations_url` |

The controller must mirror it, or you get `uninitialized constant Api::V1::OrganizationsController`:

```ruby
module Api
  module V1
    class OrganizationsController < ApplicationController
      def index
      end
    end
  end
end
```

**Folders are not created for you.** Editing `routes.rb` doesn't create files. Make them yourself:

```bash
mkdir -p app/controllers/api/v1
touch app/controllers/api/v1/organizations_controller.rb
```
or use the generator: `bin/rails generate controller api/v1/organizations index --skip-routes`. New folders are picked up automatically, with no registration and no restart in development.

## 6. `scope`: the low-level tool behind `namespace`

A route group has **three independent settings**:

| Setting | What it controls | `scope` option |
|---|---|---|
| Path | URL prefix | `path:` (or the string shortcut) |
| Module | controller class and folder | `module:` |
| Name prefix | helper name | `as:` |

`namespace :admin` is a shortcut that sets all three:

```ruby
namespace :admin do ... end
# is the same as
scope path: "admin", module: "admin", as: "admin" do ... end
```

`scope` lets you change **only some** of them. With `resources :articles` inside:

```ruby
scope "/admin" do                 # path only
  resources :articles
end
# URL /admin/articles | class ArticlesController | helper articles_url

scope module: "admin" do          # class only
  resources :articles
end
# URL /articles | class Admin::ArticlesController | helper articles_url

scope path: "/admin", module: "admin" do   # path + class, no helper prefix
  resources :articles
end
# URL /admin/articles | class Admin::ArticlesController | helper articles_url
```

Compare with `namespace :admin`, where the helper becomes `admin_articles_url`.

**When to use which:** `namespace` for versioning and groups (almost always). `scope` when you want to change fewer than three things, like a URL-only prefix or clean URLs with code in folders. If you meet `scope` in a codebase, work out which of the three it changes, and confirm with `bin/rails routes`.

## 7. Route helpers: never hard-code URLs

Every named route gets helpers. The name is the **Prefix** column of `bin/rails routes`, plus `_path` or `_url`:

```ruby
api_v1_organizations_path   # "/api/v1/organizations"
api_v1_organizations_url    # "http://localhost:3000/api/v1/organizations"
```
The verb isn't part of the name. `GET`, `POST` and `DELETE` on the same path share one helper.

**Passing values**

```ruby
api_v1_organization_url(42)                  # /api/v1/organizations/42  (fills :id)
api_v1_organization_url(org)                 # a model object uses org.id
api_v1_organization_url(id: 42)              # same, with a named argument
api_v1_organizations_url(page: 2, q: "sun")  # extra args become ?page=2&q=sun
```
**Plural** is the collection, **singular** is one record.

**Where you use them**

```ruby
# 1. in request tests
get api_v1_organizations_url, as: :json

# 2. in controllers: tell the client where the new record lives
render json: org, status: :created, location: api_v1_organization_url(org)

# 3. in the console, to check a helper
app.api_v1_organizations_path
```
Use `_url` for API responses, redirects and tests. Use `_path` when only the path matters.

**Why not strings:** a wrong helper raises `NoMethodError` right away, while a wrong string gives a quiet 404. Helpers also fill in ids and encode query strings.

## 8. Reading `bin/rails routes`

```bash
bin/rails routes -g organization       # grep by name, verb or path
bin/rails routes -c api/v1/organizations   # one controller
bin/rails routes --unused              # routes that nothing uses
```
```
Prefix                 Verb  URI Pattern                      Controller#Action
api_v1_organizations   GET   /api/v1/organizations(.:format)  api/v1/organizations#index
```
- **Prefix:** the helper name (add `_url` or `_path`).
- **`(.:format)`:** optional extension like `.json`. Parentheses mean optional.
- **Controller#Action:** what the router resolved. If it doesn't match your class name, that's your bug.

## 9. Extra routes (beyond the 7 actions)

For actions that don't fit `index/show/create/update/destroy`, add them inside `resources`.

**`member`** acts on **one** record, so it has an `:id`. **`collection`** acts on the **whole list**, with no `:id`.

```ruby
namespace :api do
  namespace :v1 do
    resources :organizations, only: [:index, :show] do
      member do
        post :archive      # POST /api/v1/organizations/:id/archive
      end
      collection do
        get :export        # GET  /api/v1/organizations/export
      end
    end
  end
end
```
One-line version:
```ruby
resources :organizations do
  post :archive, on: :member
  get  :export,  on: :collection
end
```
Helpers: `archive_api_v1_organization_url(id)` and `export_api_v1_organizations_url`. The action name goes **first**. Copy from the Prefix column.

The controller needs matching methods, or you get `The action 'archive' could not be found`:
```ruby
def archive
  org = Organization.find(params[:id])
end

def export
  # no :id, this works on the whole list
end
```
**Design tip:** if you keep adding custom actions, it may be a separate resource. `POST /organizations/42/archive` can instead be `POST /organizations/42/archival` with its own controller and the standard `create`. Rails developers prefer every controller to stay on the 7 standard actions.

## 10. Nested routes

Use them when one resource really **belongs to** another:

```ruby
namespace :api do
  namespace :v1 do
    resources :patients, only: [:index, :show, :create] do
      resources :appointments, only: [:index, :create]   # nested, one level
    end
    resources :appointments, only: [:show, :update, :destroy]   # direct, single record
  end
end
```

| Path | Controller#action | `params` |
|---|---|---|
| GET `/api/v1/patients/:patient_id/appointments` | `api/v1/appointments#index` | `params[:patient_id]` |
| POST `/api/v1/patients/:patient_id/appointments` | `api/v1/appointments#create` | `params[:patient_id]` |
| GET `/api/v1/appointments/:id` | `api/v1/appointments#show` | `params[:id]` |

- The parent id is `params[:parent_singular_name_id]`, here `params[:patient_id]`.
- The helper combines both names: `api_v1_patient_appointments_url(patient)`.
- `show/update/destroy` don't need the parent, since the appointment already knows its patient.

**Shallow nesting** gives the same result with less code: `resources :appointments, shallow: true`, nested inside `patients`.

```ruby
def index
  patient = Patient.find(params[:patient_id])
  render json: patient.appointments
end
```
**Rules:** nest at most one level, and skip nesting where the parent can come from somewhere else.

**CareSync note:** don't nest tenants. `/organizations/:id/patients` lets a user edit the URL to try another tenant's data. Use `resources :patients`, and take the tenant from the logged-in user (`Current.organization`), not from the URL.

## 11. Order matters

Routes match top to bottom, like Express. Put specific routes above general ones:
```ruby
resources :photos
get "photos/search", to: "photos#search"   # never reached: "search" matches photos/:id
```

## 12. `member`, `namespace` and the rest are just Ruby methods

They aren't keywords. Ruby has few keywords (`if`, `def`, `class`, `do`, `end`, `return`...).

```ruby
resources :organizations do
  member do
    post :archive
  end
end
```
This is all method calls with blocks. `resources` is called with `:organizations` and a block. `member` is a method available inside that block. `post` is a method with the argument `:archive`.

Rails runs the `draw do ... end` block inside a router object (`ActionDispatch::Routing::Mapper`), and that object defines `get`, `namespace`, `scope`, `resources`, `member`, `collection` and `root`. Typing `member do` in a model gives `undefined method 'member'`.

**Express comparison:** like `router.get(...)`, but Ruby lets you drop the object name and parentheses by running the block inside that object. This style is called a DSL, and it's why Rails can look like magic.

Also: `get :export, on: :collection` has `on: :collection` as a hash passed as the last argument, so it's `get(:export, { on: :collection })` with braces and parentheses written out.

Other things you'll see: `root "organizations#index"`, `defaults: { format: :json }`, `constraints: { id: /\d+/ }`.

## 13. Common errors

| Symptom | Likely cause |
|---|---|
| `No route matches [GET] "/organizations"` | route missing, wrong verb or wrong namespace. Run `bin/rails routes -g` |
| `uninitialized constant Api::V1::OrganizationsController` | class name, `module` nesting or file path doesn't match the namespace |
| `The action 'index' could not be found for ...Controller` | route is fine but the method is missing or misspelled |
| `undefined method 'api_v1_organizations_url'` | wrong helper name. Copy it from the Prefix column |
| `uninitialized constant ...` with the file in `app/controllers/` and the `Api::V1` modules in it | file path doesn't mirror the module nesting |

## 14. For CareSync

```ruby
# config/routes.rb (today)
Rails.application.routes.draw do
  get "up" => "rails/health#show", as: :rails_health_check

  namespace :api do
    namespace :v1 do
      resources :organizations, only: :index
    end
  end
end
```
Check with `bin/rails routes -g organization`. Add extra and nested routes only when the controller exists, and use `bin/rails routes --unused` to catch leftovers.

## 15. Self-check

1. What does `"api/v1/organizations#index"` resolve to, as a class, a file and a method?
2. Which two routes share the path `/organizations/42`? What tells them apart?
3. Why `only: :index` and not `resources :organizations` in an API?
4. `namespace :admin` is shorthand for which `scope` call?
5. What URL, class and helper does `scope "/v1", module: "api" do resources :organizations, only: :index end` produce?
6. What's the difference between a `member` and a `collection` route, and which one has `:id`?
7. In nested `patients/appointments`, why doesn't the `show` helper need the patient?
8. Is `member` a Ruby keyword? What is it?

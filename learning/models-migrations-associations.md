# Migrations, associations and DB constraints

Sources: [Active Record Migrations](https://guides.rubyonrails.org/active_record_migrations.html), [Association Basics](https://guides.rubyonrails.org/association_basics.html), [Active Record Validations](https://guides.rubyonrails.org/active_record_validations.html) (see [active-record-validations.md](active-record-validations.md)).

## 1. Migrations = versioned schema changes
A migration is a Ruby file in `db/migrate/` named `<timestamp>_<name>.rb`. `bin/rails db:migrate` runs the ones not yet applied (tracked in the `schema_migrations` table) and rewrites `db/schema.rb`, the snapshot of the current schema.
Express comparison: Knex/Sequelize migrations. `change` is reversible, so Rails can roll it back (`bin/rails db:rollback`) by itself.

```ruby
create_table :patients do |t|
  t.references :organization, null: false, foreign_key: true   # organization_id + index + FK
  t.string :first_name, null: false
  t.timestamps                                                  # created_at, updated_at
  t.index [:organization_id, :last_name]                        # composite index
end
```
Rule: **never edit a migration that has been committed and run elsewhere.** Add a new one. (Editing is fine locally before it's shared.)

## 2. Database constraints vs model validations
Both are needed, they protect different things:

| | Model validation | DB constraint |
|---|---|---|
| Where | Ruby (`validates`) | Postgres (`null: false`, unique index, foreign key) |
| Gives | friendly error messages | a guarantee, even for races, console edits, `update_all`, other apps |
| Example | `validates :email, presence: true, uniqueness: true` | `null: false` plus `t.index :email, unique: true` |

Uniqueness validation alone has a race (two requests at once). The unique index is what really enforces it. Same for foreign keys: `foreign_key: true` makes Postgres reject a `patients` row whose `organization_id` doesn't exist.

## 3. Associations
```ruby
class Organization < ApplicationRecord
  has_many :users
  has_many :patients
end

class Patient < ApplicationRecord
  belongs_to :organization      # required by default in Rails: fails validation if missing
end
```
- `belongs_to` goes on the model whose table has the `organization_id` column (the "many" side).
- `has_many` gives `organization.patients` (a query, not an array). `organization.patients.create!(...)` sets the FK for you.
- `belongs_to` is required by default, so no `presence` validation is needed for it.

### `dependent:` (what happens on delete)
The FK stops you from deleting an organization that still has patients (Postgres raises `ActiveRecord::InvalidForeignKey`). Options on `has_many`:
| Option | Effect |
|---|---|
| (none) | the delete fails with an FK error |
| `dependent: :restrict_with_exception` | raises `ActiveRecord::DeleteRestrictionError` before hitting the DB |
| `dependent: :destroy` | destroys children first (runs their callbacks) |
| `dependent: :delete_all` | SQL delete of children, no callbacks |
For PHI, **never cascade-delete by accident**. Prefer `:restrict_with_exception`.

## 4. Enums (for `role`)
```ruby
enum :role, { admin: "admin", provider: "provider", nurse: "nurse", front_desk: "front_desk" }
```
Gives `user.admin?`, `user.admin!`, `User.admin` scope, and (with `validate: true`) rejects unknown values. Use string-valued enums so the DB stays readable.

## 5. `has_secure_password` (preview for step 5)
Needs the `bcrypt` gem and a `password_digest` column (already in `users`). Adds `password=` and `authenticate`. We add it in the auth step, so for now `User` simply has the column.

## 6. Normalizing and validating email
```ruby
normalizes :email, with: ->(e) { e.strip.downcase }
validates :email, presence: true, uniqueness: true, format: { with: URI::MailTo::EMAIL_REGEXP }
```
`normalizes` (Rails 7.1+) cleans the value on assignment, so "A@x.com " and "a@x.com" can't both exist.

## 7. Self-check questions
1. Why do we have both `validates ... uniqueness: true` and a unique index on `email`?
2. What does `t.references :organization, foreign_key: true` create in the table?
3. A patient insert with `organization_id: 9999` and no matching organization: which layer rejects it, and with what error?
4. What happens when you call `destroy!` on an organization that has patients, with and without `dependent:`?
5. Why is `has_many :patients` on `Organization` and `belongs_to :organization` on `Patient`, not the other way?

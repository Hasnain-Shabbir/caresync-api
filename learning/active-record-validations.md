# Active Record Validations

Source: [Rails Guides: Active Record Validations](https://guides.rubyonrails.org/active_record_validations.html)
Express comparison: like Joi/Zod or Mongoose validators, but declared on the model, so every code path that saves goes through them.

## When they run
- `save`, `create`, `update` run validations. If invalid they return `false` and nothing is written.
- `save!`, `create!`, `update!` raise `ActiveRecord::RecordInvalid` instead.
- `Model.new(...)` does **not** validate. `errors` stays empty until you call `valid?` or save.

```ruby
org = Organization.new(name: nil)
org.valid?                 # => false
org.errors[:name]          # => ["can't be blank"]
org.errors.full_messages   # => ["Name can't be blank"]
```

## Methods that skip validations (be careful)
`update_column(s)`, `update_attribute`, `update_all`, `touch`, `increment!`, `insert_all`, `upsert_all`, `save(validate: false)`.
Rule: if an invariant really matters, back it with a DB constraint, not only a validation.

## Helpers you'll use most
```ruby
validates :name,  presence: true
validates :email, uniqueness: { case_sensitive: false }
validates :bio,   length: { maximum: 500 }          # also minimum, in, is
validates :code,  format: { with: /\A[a-z]+\z/ }
validates :age,   numericality: { only_integer: true, greater_than: 0 }
validates :role,  inclusion: { in: %w[admin nurse] }
validates :ends_at, comparison: { greater_than: :starts_at }
```

## Options
| Option | Meaning |
|---|---|
| `allow_nil: true` | skip when value is `nil` |
| `allow_blank: true` | skip when nil or whitespace |
| `message: "..."` | custom error text |
| `on: :create` / `:update` | only in that lifecycle |
| `if:` / `unless:` | conditional (symbol or lambda) |
| `uniqueness: { scope: :org_id }` | unique within a group (multi-tenancy!) |

## Custom validation
```ruby
validate :due_date_not_in_past

def due_date_not_in_past
  errors.add(:due_date, "can't be in the past") if due_date && due_date < Date.today
end
```
For reusable logic, write an `ActiveModel::Validator` subclass and use `validates_with`.

## The uniqueness race condition (why we also have a DB index)
`uniqueness` runs a `SELECT` first, then `INSERT`. Two simultaneous requests can both pass the check and insert duplicates. Only a **unique index** in the database is airtight.
Validation gives friendly errors, the index gives the guarantee. Use both.
For `scope:` uniqueness, the index must cover all the scoped columns, e.g. `add_index :users, [:organization_id, :email], unique: true`.

## For CareSync
- `Organization`: `validates :name, presence: true, uniqueness: true` plus the unique index.
- Later, users are unique **per organization**, so use `scope: :organization_id`.

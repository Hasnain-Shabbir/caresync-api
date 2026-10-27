# Guide 08: Password reset (mailer + background job + two mutations)

You type the code. This guide explains **why** first, then **what to type**.
Sources: [Devise `Recoverable` API](https://www.rubydoc.info/gems/devise/Devise/Models/Recoverable), [Devise wiki: Use Active Job to send emails](https://github.com/heartcombo/devise#activejob-integration) (README section "ActiveJob Integration"), [Rails Guides: Action Mailer Basics](https://guides.rubyonrails.org/action_mailer_basics.html), [Rails Guides: Active Job Basics](https://guides.rubyonrails.org/active_job_basics.html), [OWASP Forgot Password Cheat Sheet](https://cheatsheetseries.owasp.org/cheatsheets/Forgot_Password_Cheat_Sheet.html).

**Not run or verified by me:** none of the code below has been executed. I read the repo (User model, `devise_for ... skip: :all`, queue config, mailer layout) and wrote this from Devise's documented API. Places where I'm unsure are marked **CHECK**.

Goal: a user who forgot their password calls `requestPasswordReset(email)`, gets an email with a token, then calls `resetPassword(token, password, passwordConfirmation)`. The email is sent **in the background**, and the response never reveals whether the email exists.

---

## 1. Concepts

### How Devise `recoverable` works (already installed, columns exist)
- `User.send_reset_password_instructions(email: ...)` finds the user, generates a random **raw token**, stores only its **digest** in `reset_password_token`, sets `reset_password_sent_at`, and calls the mailer with the raw token.
- `User.reset_password_by_token(reset_password_token:, password:, password_confirmation:)` digests the incoming token, finds the user, checks it's not older than `reset_password_within` (6 hours in our initializer), validates the new password, saves. It returns the user; **check `user.errors`** for failure.
- Express comparison: this is the `crypto.randomBytes` token + hashed-in-DB + expiry flow you would hand-write, already done.

### Why the email goes through a background job
Sending SMTP inside the request is slow and can fail. Worse for security: **response time leaks whether the email exists** (found = slow, not found = fast). Enqueueing makes both paths fast. Rails has this built in: `deliver_later` puts the mail in Active Job, and **Solid Queue** (already in the Gemfile, production queue DB configured) runs it. Express comparison: BullMQ plus a worker.

### Devise needs a nudge to use `deliver_later`
Devise calls `deliver_now` by default. The README's documented fix is to override `send_devise_notification` in the model.

### No frontend routes here
We have `devise_for :users, skip: :all`, so there are **no** `edit_user_password_url` helpers. Devise's default reset email template uses one, so **it would raise**. We must write our own mail template that links to the **frontend**, for example `https://app.example.com/reset-password?token=...`. The frontend then calls our `resetPassword` mutation.

### Security rules for this flow (the HIPAA-style part)
| Rule | How we meet it |
|---|---|
| Don't reveal whether an email has an account (user enumeration) | `requestPasswordReset` **always** returns success |
| Token is single use and short lived | Devise clears it on success, 6 hour expiry |
| Token not stored in plain text | Devise stores a digest |
| After a reset, old sessions must die | We delete the user's allowlisted JWTs |
| A locked user who resets should be able to get in | We unlock after a successful reset (decision, see step 5) |
| Don't log tokens or passwords | `filter_parameters` already has `:token` and `:passw` (**CHECK** it covers job arguments in logs, see step 7) |

Known limit: with `deliver_later`, the raw token sits in the job arguments in the queue DB until the job runs. It's short lived and the queue DB is internal, but say so in your README's risk notes.

---

## 2. Steps

### Step 1. Set a real mailer sender
`config/initializers/devise.rb` line 27 is still the placeholder. Change `config.mailer_sender` to something like `"CareSync <no-reply@caresync.example>"`.

### Step 2. Send Devise mails in the background
In `app/models/user.rb`, add:

```ruby
def send_devise_notification(notification, *args)
  devise_mailer.send(notification, self, *args).deliver_later
end
```

Put it under `protected` (Devise's README shows it that way). `self` becomes a GlobalID (the job re-loads the user), `*args` carries the raw token string.

### Step 3. Where the frontend lives
Add one config value so the link isn't hard-coded. In `config/application.rb`:

```ruby
config.x.frontend_url = ENV.fetch("FRONTEND_URL", "http://localhost:3000")
```

(Add `FRONTEND_URL` to your production env later. Mark it in the README.)

### Step 4. Your own reset email template
Create `app/views/devise/mailer/reset_password_instructions.html.erb` (Devise looks here first, **CHECK** by running the test in step 6, it fails loudly if the template is wrong):

```erb
<p>Hello <%= @resource.first_name %>,</p>

<p>Someone asked to reset your CareSync password. Use the link below within 6 hours.</p>

<p><%= link_to "Reset my password", "#{Rails.configuration.x.frontend_url}/reset-password?token=#{@token}" %></p>

<p>If you did not ask for this, ignore this email. Your password stays the same.</p>
```

Do **not** put any patient data in the email. Email is not a secure channel.

### Step 5. The two mutations
Follow [guide-adding-a-crud-resource.md](guide-adding-a-crud-resource.md) for the register-in-`mutation_type.rb` step.

**`app/graphql/mutations/request_password_reset.rb`**
- Input: `email` (String, required).
- Must work **without** a token, so override `ready?` to return `true` exactly like `Login` does.
- `resolve`: call `User.send_reset_password_instructions(email: email)` and **ignore the result**. Always return `{ success: true }` (field `success`, Boolean, null: false).
- Why ignore the result: an unknown email returns a user with errors. If you returned them, you'd leak which emails exist.

**`app/graphql/mutations/reset_password.rb`**
- Inputs: `token`, `password`, `password_confirmation` (all String, required).
- Also overrides `ready?` to `true` (the user has no session, that is the point).
- `resolve`:
  1. `user = User.reset_password_by_token(reset_password_token: token, password: password, password_confirmation: password_confirmation)`
  2. If `user.errors.empty?`: delete their sessions with `user.allowlisted_jwts.destroy_all`, and unlock with `user.unlock_access!` if `user.access_locked?`. Return `{ success: true, errors: [] }`.
  3. Else return `{ success: false, errors: user_errors_from(user) }` (the helper from `BaseMutation` gives `VALIDATION_FAILED`).
- Wrong or expired token: Devise puts an error on `reset_password_token` ("is invalid"). It comes back as a `VALIDATION_FAILED` error at `path: ["input", "resetPasswordToken"]`. That's fine, it doesn't reveal accounts.

Decision to make and write in your README: **unlock after reset?** Yes is the usual choice (the reset proves email ownership). The trade-off is that an attacker who controls the mailbox gets in anyway, so the mailbox is the real trust anchor.

### Step 6. Tests (write these first if you want, they define the behavior)
Create `test/graphql/password_reset_test.rb`. Use the helpers your other GraphQL tests use (`execute`). Cases:

1. **Request for a known email enqueues one mail**: `assert_enqueued_jobs 1` (include `ActiveJob::TestHelper`, or use `assert_enqueued_emails 1`), and the user now has a `reset_password_token` digest.
2. **Request for an unknown email gives the same response and enqueues nothing**: same `{ success: true }`, `assert_no_enqueued_jobs`. This is the enumeration test. Compare the two responses with `assert_equal`.
3. **Mail content**: run `perform_enqueued_jobs { request }`, then `ActionMailer::Base.deliveries.last`. Assert `to`, subject, that the body contains `/reset-password?token=`, and that it contains **no** patient names.
4. **Valid token changes the password**: you need the raw token. Get it with `user.send_reset_password_instructions` (returns the raw token). Then call `resetPassword`, then check `user.reload.valid_password?("NewPassw0rd!")`.
5. **Token is single use**: call `resetPassword` twice with the same token, second returns a `VALIDATION_FAILED` error.
6. **Expired token**: `travel 7.hours` before the call, expect the error.
7. **Weak or mismatched password** returns `VALIDATION_FAILED`, password unchanged.
8. **Old JWT stops working**: log in first (get a token), reset the password, then call a protected query with the old token and expect `UNAUTHENTICATED`.
9. **Locked user can log in after reset**: set `locked_at` and `failed_attempts`, reset, then `login` succeeds.
10. **Default-deny test still passes**: your existing "every mutation requires login" test (if it lists mutations) will need these two added to its exceptions. Run the suite and read the failure message.

### Step 7. Check the logs don't leak the token
Run `bin/rails test`, then open `log/test.log` and search for `reset_password_token` and for the raw token text. Devise's own mail job args may be printed by Active Job's enqueue log. **CHECK:** Rails filters `filter_parameters` in request params, but I am not sure it filters job arguments in the Active Job log line. If you see a raw token, tell me and we decide (usually: `config.active_job.log_arguments = false` for production).

### Step 8. Manual check in dev
1. Start the server (`bin/rails s -p 4000`). In dev the queue adapter defaults to async (in-process), and mail only logs unless you set a delivery method, so look in `log/development.log` for the email body. **CHECK:** development.rb has `raise_delivery_errors = false` and no `delivery_method`, so I expect SMTP to be attempted to localhost and fail silently. Add `config.action_mailer.delivery_method = :file` if you want files in `tmp/mails`.
2. Run `requestPasswordReset`, copy the token from the log, call `resetPassword`, then `login` with the new password.

---

## 3. Self-check (try first, answers below)

1. Why does `requestPasswordReset` ignore Devise's return value?
2. Why must both new mutations override `ready?`?
3. Why do we delete the allowlisted JWTs after a reset?
4. What breaks if you keep Devise's default reset email template?
5. Why is `deliver_later` also a security feature here, not only a speed one?

**Answers**
1. Devise returns a user with errors for unknown emails. Returning that would reveal which emails have accounts.
2. `BaseMutation#ready?` requires login (default-deny). Someone resetting a password has no token.
3. If the password was stolen, a stolen session token could stay valid for up to 30 minutes after the reset. Deleting the allowlist rows kills them immediately.
4. It calls `edit_user_password_url`, which doesn't exist because of `devise_for ... skip: :all`. The mailer raises.
5. A synchronous send makes "email exists" slower than "email unknown", so timing reveals accounts. Enqueueing makes both paths take about the same time.

## 4. Takeaway (write your own, 2 lines)
Write what you learned in your own words in your notes, as agreed.

## 5. Commit plan (when you ask me to commit)
- `chore: set devise mailer sender and frontend url config`
- `feat: add password reset mutations with background email`
- `test: add password reset tests`

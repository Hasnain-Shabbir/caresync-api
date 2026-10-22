---
name: webhook-integration
description: Add an inbound webhook or external provider safely (signature check, inbox table, idempotent job, replay test). Run manually with /webhook-integration when the first integration is added.
disable-model-invocation: true
---

# Add a webhook or provider integration

CareSync has no integrations yet. Read `.claude/rules/integrations-and-webhooks.md` first. Ask the owner which provider, which events, and what data (PHI?) it carries.

## Steps
1. **Folder** `app/integrations/<provider>/` for the client, the signature validator, and payload mappers (small classes).
2. **Verify first.** The controller verifies the provider's signature or shared secret with a constant-time comparison before reading anything else. Failure returns 401 and stores nothing.
3. **Inbox table.** Store the raw payload with a **unique provider event id** (unique index). A replayed event hits the unique index and is acknowledged, not processed twice.
4. **Process in a job.** The controller stores and enqueues, then answers 2xx quickly. The job loads by id and calls a service.
5. **Idempotent service.** Running it twice is safe. Outbound calls have timeouts and idempotency keys when they move money or create records.
6. **Secrets** in Rails credentials. Never in code, logs, or fixtures. Do not log full payloads with personal data.
7. **Reconcile** money or state with a scheduled job.

## Tests
- Valid signature is processed.
- Invalid or missing signature returns 401 and stores nothing.
- The same event twice is processed once.
- A failing job retries and is visible, not dropped.
- No real network (stub the provider).

## Done when
`bin/rails test`, `bin/rubocop`, `bin/brakeman -q` pass, and `security-review-backend` finds nothing new.

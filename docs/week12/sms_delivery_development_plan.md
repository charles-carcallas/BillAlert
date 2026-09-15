# Week 12 — httpSMS delivery development plan

**Milestone:** API or device feature integration complete  
**Outcome:** a BillAlert SMS queued by the database is handed to httpSMS,
sent by gateway phone ending 8974, and updated from an authenticated
httpSMS webhook without exposing credentials to Flutter or Git.

This plan covers the next development step only: SMS delivery. The existing
billing rules remain server-owned, BillAlert still does not calculate a bill
amount, and no SMS provider secret enters the mobile application.

## 1. Current starting point

Already present:

- `notifications` records `sms` and `push` rows with `pending`, `sent`, or
  `failed` status.
- `fn_issue_disconnection_notice` queues a disconnection SMS.
- `v_due_for_overdue_notice` identifies bills due for an overdue alert.
- `settings` owns the SMS template, batch size, delay, and retry limit.
- Consumer numbers are normalized to Philippine E.164 by the database.
- Supabase already holds `HTTPSMS_API_KEY` and `HTTPSMS_PHONE_NUMBER` as Edge
  Function secrets.

Missing:

- no process queues overdue SMS rows;
- no process claims and sends pending SMS rows;
- no provider message ID or delivery timestamp is stored;
- no webhook applies sent, delivered, failed, or expired events;
- no scheduled job invokes an SMS worker;
- no live phone delivery has been recorded as Week 12 evidence.

## 2. Provider contract to implement

The sender calls:

```text
POST https://api.httpsms.com/v1/messages/send
x-api-key: HTTPSMS_API_KEY
Content-Type: application/json

{
  "from": HTTPSMS_PHONE_NUMBER,
  "to": "+639...",
  "content": "...",
  "request_id": "<BillAlert notification UUID>"
}
```

A successful request returns HTTP `200`; the provider message ID is
`data.id`. `request_id` links the provider record to BillAlert. The public
httpSMS documentation does not promise that repeating a `request_id` is
idempotent, so a timeout must not trigger an automatic duplicate send.

Webhook requests:

- use `X-Event-Type` for the event name;
- carry a Bearer JWT signed with HS256 and the configured webhook signing key;
- use CloudEvents JSON;
- must receive a response within five seconds;
- may be retried after a 5xx response.

Events in scope are `message.phone.sent`, `message.phone.delivered`,
`message.send.failed`, and `message.send.expired`.

References:

- https://docs.httpsms.com/
- https://docs.httpsms.com/webhooks/introduction
- https://docs.httpsms.com/webhooks/events
- https://supabase.com/docs/guides/functions/schedule-functions

## 3. Design rules

1. **Server only.** Flutter never calls httpSMS and never receives its API
   key. The Edge Function owns the provider request.
2. **Snapshot the destination.** Save the normalized destination number when
   the notification is queued. Editing a household number later must not
   silently redirect an already queued notice.
3. **Durable claims.** A database transaction records a claim before any HTTP
   request. `FOR UPDATE SKIP LOCKED` alone is insufficient because the lock
   ends before the provider call.
4. **No blind resend after uncertainty.** A timeout, lost connection, worker
   crash, or 5xx response can occur after httpSMS accepted the message. Mark
   that attempt `uncertain` for reconciliation. Retry only after confirming
   that httpSMS has no record for the BillAlert `request_id`, unless provider
   testing proves duplicate `request_id` values are rejected.
5. **Provider acceptance is not delivery.** HTTP `200` means accepted. Only
   webhook events may mark the message sent or delivered.
6. **Idempotent and out-of-order webhooks.** Repeated events do nothing harmful.
   A delivered event may set both sent and delivered timestamps if the sent
   event arrives later or never arrives. A later failed event cannot overwrite
   a delivered result.
7. **Catch missed overdue runs.** The queue function processes every eligible
   overdue bill up to today, not only bills matching today's exact date. The
   existing unique index still guarantees one overdue notification per bill.
8. **Protect delivery fields.** A consumer may read an SMS row and mark it
   read, but cannot forge provider IDs, delivery state, failure details, or
   timestamps through PostgREST.
9. **Minimize logged personal data.** Logs use notification IDs and masked
   phone endings. They never print the API key, full phone number, or message
   content.

## 4. Phase A — migration `13_sms_delivery.sql`

### A1. Add delivery metadata

Add fields to `notifications`:

| Field | Purpose |
|---|---|
| `destination_number` | E.164 destination captured at queue time |
| `gateway_message_id` | `data.id` returned by httpSMS; partial unique index |
| `dispatch_state` | `ready`, `claimed`, `accepted`, or `uncertain` |
| `claim_token` | identifies the worker that owns the current claim |
| `claimed_at` | proves when ownership began |
| `accepted_at` | provider accepted the request |
| `last_attempted_at` | last HTTP attempt |
| `delivered_at` | delivery webhook timestamp |

Keep `notifications.status` as the application-facing state:

- `pending`: ready, claimed, accepted, or uncertain;
- `sent`: the gateway phone reported sent or delivered;
- `failed`: a definitive provider failure, expiration, missing number, or
  exhausted manual retry decision.

Backfill `destination_number` only for existing pending SMS rows from their
current household number. Existing rows without a number remain failed.

### A2. Update notification queuing

Update `fn_queue_notification` so SMS rows snapshot `contact_number` into
`destination_number`. Preserve the existing behavior that a missing number
creates a visible failed row with a reason.

### A3. Queue overdue notifications

Add server-only `fn_queue_overdue_sms(p_today date default fn_ph_today())`:

- selects priced, unpaid bills where
  `due_date + settings.overdue_days_after <= p_today`;
- excludes bills with an existing overdue notification;
- renders the established database template;
- queues using `settings.overdue_channel`;
- returns counts for queued, already present, and failed-no-number rows.

Repeated calls must create no duplicate notification.

### A4. Claim a batch atomically

Add server-only `fn_claim_sms_batch(p_claim_token uuid)`:

- reads `settings.batch_enabled` and `settings.batch_size`;
- selects pending SMS with `dispatch_state = 'ready'`, a destination, and no
  gateway ID;
- orders oldest first;
- uses `FOR UPDATE SKIP LOCKED`;
- changes the selected rows to `claimed`, records token and time, and increments
  `retry_count` in the same transaction;
- returns only the fields required to send: notification ID, destination, and
  message content.

An abandoned expired claim moves to `uncertain`; it is not automatically
returned to `ready`.

### A5. Record outcomes

Add server-only functions:

- `fn_record_sms_acceptance(notification, claim, gateway_id, accepted_at)`;
- `fn_record_sms_definitive_failure(notification, claim, reason)`;
- `fn_record_sms_uncertain(notification, claim, reason)`;
- `fn_apply_sms_event(gateway_id, event_type, event_at, reason)`.

All functions verify the expected current state. Gateway IDs are unique. Event
application is safe when called repeatedly or out of order.

### A6. Lock down access

- Revoke these functions from `public`, `anon`, and `authenticated`.
- Grant execution only to `service_role`.
- Prevent client roles from changing the new gateway fields or SMS delivery
  status directly.
- Preserve the consumer's ability to mark their own Inbox row read.
- Preserve existing area-scoped staff visibility.

## 5. Phase B — Edge Function `send-sms`

Create `supabase/functions/send-sms/index.ts`.

Request security:

- accept POST only;
- deploy without platform JWT verification because the caller is Cron;
- require a dedicated `SMS_CRON_SECRET` header;
- compare the provided secret before performing any database or provider work;
- use the injected service-role credential only inside the function.

Processing sequence:

1. Call `fn_queue_overdue_sms`.
2. Generate one claim token and call `fn_claim_sms_batch`.
3. Process the returned rows sequentially.
4. Wait `settings.batch_delay_ms` between provider calls; the httpSMS phone
   also enforces its own messages-per-minute limit.
5. Send the notification UUID as `request_id`.
6. On HTTP `200` with a valid `data.id`, record acceptance and leave status
   pending until a webhook arrives.
7. On a clear 400, 401, or 422 response, store a safe failure reason.
8. On timeout, network failure, malformed success response, 5xx, or a crash
   boundary, record or later classify the claim as uncertain. Do not blindly
   resend it.
9. Return a summary containing counts only: queued, claimed, accepted, failed,
   and uncertain.

Never return or log secrets, complete numbers, or SMS content.

## 6. Phase C — Edge Function `httpsms-webhook`

Create `supabase/functions/httpsms-webhook/index.ts`.

- Deploy without Supabase JWT verification because httpSMS is the caller.
- Require `Authorization: Bearer <JWT>`.
- Verify HS256 with `HTTPSMS_WEBHOOK_SIGNING_KEY`; reject missing, invalid, or
  differently signed tokens.
- Require JSON and validate `X-Event-Type` against the four allowed events.
- Read the gateway message ID and timestamp from event-specific payloads.
  Capture real test-webhook fixtures before finalizing these paths because the
  public event reference is brief and fields may differ by event.
- Call `fn_apply_sms_event` with the service-role client.
- Return `200` for an authenticated duplicate or unknown gateway ID so httpSMS
  does not retry forever; log only the event ID and masked gateway ID.
- Return quickly within the provider's five-second timeout.

## 7. Phase D — scheduler and secrets

Two additional values are required:

- Edge Function secret `HTTPSMS_WEBHOOK_SIGNING_KEY`;
- Edge Function secret `SMS_CRON_SECRET`.

Store the Cron copy of `SMS_CRON_SECRET` in Supabase Vault. Do not place either
value in a migration, Flutter config, README, command history, or GitHub.

Enable Supabase Cron and `pg_net`, then create one job that invokes `send-sms`
every 15 minutes. Create the job only after the migration and both functions
have passed manual smoke tests. The job must have a stable name and migration
logic must avoid creating duplicates when redeployed.

## 8. Phase E — automated verification

### SQL regression test

Create `supabase/tests/sms_delivery_test.sql`, wrapped in a transaction and
rolled back. Prove:

- overdue queueing catches a missed day and remains one-per-bill;
- no-number SMS creates a failed row with a reason;
- destination number is snapshotted;
- two workers cannot claim the same row;
- a claim persists after the transaction;
- accepted, sent, delivered, failed, and expired transitions are correct;
- duplicate and out-of-order webhooks are harmless;
- delivered cannot regress to failed;
- anon, authenticated consumer, and staff roles cannot call service functions
  or forge gateway fields.

### Edge Function tests

Use a mock httpSMS endpoint and fixture webhook payloads. Prove:

- the exact request method, URL, headers, and JSON contract;
- notification UUID is passed as `request_id`;
- accepted, definite failure, and uncertain outcomes map correctly;
- invalid Cron secret is rejected before work starts;
- invalid webhook JWT, algorithm, event, and payload are rejected;
- secrets and full phone numbers never appear in logs or responses.

### Existing project checks

- run the complete Flutter test suite;
- run `flutter analyze` and preserve the known `scratch/`-only baseline;
- run the vocabulary/architecture test;
- scan tracked files and commit diff for API-key material.

## 9. Phase F — deployment order

1. Commit or otherwise checkpoint the existing household-account work before
   beginning SMS implementation; the current tree already contains unrelated
   changes.
2. Apply migration 13.
3. Add `HTTPSMS_WEBHOOK_SIGNING_KEY` and `SMS_CRON_SECRET` privately.
4. Deploy `send-sms` and `httpsms-webhook`.
5. Invoke each function with invalid authentication and confirm rejection.
6. Send a signed test webhook and confirm it is accepted without changing an
   unrelated row.
7. In httpSMS Settings → Webhooks, register the deployed webhook URL, signing
   key, gateway phone ending 8974, and the four message events.
8. Queue exactly one controlled SMS for a fictional demo household whose
   contact number is a consenting team member's phone.
9. Invoke `send-sms` manually and verify database `pending → sent`, then
   `delivered_at` when supported by the carrier.
10. Enable the 15-minute Cron job last.

Deploying SQL through the editor does not prove RLS. Read the result through
PostgREST or the Edge Function using the relevant authenticated role.

## 10. Phase G — device evidence

Record one end-to-end example in `docs/week12/evidence_log.md`:

| Evidence | Required value |
|---|---|
| BillAlert notification ID | database UUID |
| Notification type | overdue or disconnection |
| Consumer | fictional demo household and masked destination |
| Queue time | database timestamp |
| httpSMS gateway message ID | provider ID |
| Accepted time | Edge Function record |
| Sent time | verified webhook timestamp |
| Delivered time | webhook timestamp, or honest carrier limitation |
| Phone evidence | screenshot showing receipt on the consenting phone |
| Duplicate check | one database row and one received SMS |

Also prove the gateway phone ending 8974 is online and that a consumer without
a contact number receives a recorded failed row rather than a silently missing
alert.

## 11. Completion criteria

SMS is complete only when all of the following are true:

- no credential exists in tracked source or Flutter configuration;
- only server-side code can send or alter delivery evidence;
- overdue and disconnection SMS rows are queued once;
- the gateway phone sends a controlled message to a real phone;
- provider acceptance, sent, delivered, failed, and uncertain outcomes remain
  distinguishable;
- duplicate workers and webhook retries do not duplicate or corrupt state;
- the Cron job runs successfully and its history is visible;
- automated tests pass and the live evidence log contains IDs and timestamps.

## 12. Safe pause and rollback

If live delivery behaves unexpectedly:

1. disable the Cron job;
2. leave queued/uncertain rows intact for diagnosis;
3. do not manually reset an uncertain row until the httpSMS dashboard has been
   checked for its `request_id`;
4. keep the Edge Functions deployed for log inspection;
5. rotate the API or webhook key immediately if logs or source expose it.

No delete is required to stop sending. Disabling Cron is the first control.

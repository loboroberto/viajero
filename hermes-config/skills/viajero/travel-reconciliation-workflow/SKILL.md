---
name: travel-reconciliation-workflow
description: >
  The routine mailbox-to-calendar reconciliation umbrella: scan the travel mailbox, parse
  provider/TMC emails into StandardBooking via the parser skills, reconcile them to the
  calendar with managing-calendar-travel, forward business receipts if enabled, and
  archive — silently. Use for the hourly reconciliation cycle.
version: 1.0.0
tags: [travel, reconciliation, workflow, orchestrator]
---

# Travel Reconciliation Workflow

The end-to-end reconciliation cycle that ties the travel skills together: mailbox scan →
parse → calendar reconcile → (optional) receipt forward → archive. It ends `[SILENT]`
whenever nothing actionable happened (AGENTS.md §7 / SOUL — silence is a feature). This is
the skill the `travel-reconciliation-hygiene` cron job runs.

## When to Use

- The hourly reconciliation cron, or an on-demand "reconcile my travel" request.
- **Provisional gate:** if the configuration floor (`travel_email_account` and the rest)
  is unset, do nothing and reply exactly `[SILENT]` (AGENTS.md §1.1 — fail closed).

## Procedure

1. **Scan** `travel_email_account` for unprocessed provider/TMC mail — match senders and
   subjects against `references/provider-patterns.md`, excluding
   `-label:<travel_bookings_label>`. Gmail mechanics: `references/gmail-ops.md`.
2. **Parse** each message with the matching parser skill
   (`parsing-provider-booking-<provider>` or `parsing-corporate-tmc-booking`) into
   StandardBooking JSON (`references/standard-booking-schema.md`). When
   `employer_definition_file` is set, an email matching the active employer definition's
   assignment senders/codes is routed to `parsing-employer-assignment` instead (skip this
   branch entirely for personal-only travelers — no employer configured).
3. **Reconcile** every StandardBooking with `managing-calendar-travel` — dedup by the
   RFC 822 `Message-ID` (update, never duplicate), with colors / time format / raw URLs
   per `references/calendar-conventions.md`.
4. **Forward receipts** only when expense forwarding is enabled *and* the booking is
   business-travel (`references/expense-forwarding.md`); then archive under
   `travel_bookings_label`.
5. **Silence is the default outcome.** Reply exactly `[SILENT]` unless a genuine booking
   conflict or infrastructure failure needs the operator.

All Google calls use the `google_api.py` contract in `references/gmail-ops.md` (undotted
path `/data/hermes/skills/productivity/google-workspace/scripts/google_api.py`).

## Pitfalls

- The Gmail search query is **positional** (there is no `--query` flag); pass
  `'from:(...) is:unread'` directly. Archive with `gmail modify <ID> --remove-labels
  UNREAD,INBOX` (no space after the comma) — see `references/gmail-ops.md`.
- If `google_api.py` raises `ModuleNotFoundError: googleapiclient`, the google libraries
  ship in the image and are on the default path — run in the agent's normal execution
  context rather than hard-coding an alternate library path.
- Don't fight infrastructure: on a transient API error, pivot or retry once, then
  escalate — no tight retry loops.

## Verification

- A cycle with no new mail replies exactly `[SILENT]`.
- New bookings appear once on the calendar (no duplicate on re-run) and the source mail is
  labeled and archived.

## Anomalies

Escalate to `dm_chat_id` only on an unrecoverable infrastructure failure (auth broken, API
persistently down) — never routine travel updates.

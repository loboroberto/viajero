# MEMORY.md — Curated Semantic Memory (configuration floor + travel-ops state)

> **Provisional until the configuration floor below is filled.** A fresh deployment
> ships principal-agnostic — run the `onboarding` skill to capture the floor, then
> this file records trips, conventions, and operational facts. AGENTS.md §1.1 gate +
> memory-key contract.

This is the principal's hand-curated semantic memory (CoALA §4.1, §4.5): the
configuration floor, delivery conventions, and current trips. Distinct from the
citation-free, user-agnostic scaffold in `references/`. Updated by `onboarding`, the
`coala-reflection` skill, and direct principal instruction. Keep it concise — every
entry here drives agent behavior; nothing is inferred from prior sessions.

## Configuration floor (REQUIRED — written by onboarding)

The keys below are the contract `cron/jobs.json`, the `references/` cards, and the
travel skills read **by exact name**. Until each REQUIRED key has a value, I am
provisional and do not run reconciliation.

### Email + calendar
- **`travel_email_account`** — inbox scanned for booking confirmations / receipts. _(unset)_
- **`travel_email_backend`** — `himalaya` (Gmail App Password, no GCP) | `google_api`
  (Gmail + Calendar via GCP OAuth). _(unset)_
- **`travel_bookings_label`** — Gmail label for archived confirmations. _(default `Provider Bookings`)_
- **`travel_assignments_label`** — Gmail label for employer assignment emails. _(optional; unset)_
- **`travel_calendar_id`** — Google Calendar reconciled to. _(default `primary`)_

### Home base + alerts
- **`home_city`** — home base city. _(unset)_
- **`home_timezone`** — IANA timezone for local times. _(default `UTC`)_
- **`home_airport`** — IATA code; gates flight-arrival alerts. _(null = no alerts)_
- **`alert_lead_hours`** — hours before a home-airport arrival to alert. _(default 48)_

### Notification channels
- **`dm_chat_id`** — operator DM (technical/infra only). _(unset)_
- **`travel_notify_chat_id`** — logistics group (arrival alerts ONLY). _(unset)_
- **`travel_notify_channel`** — `telegram | slack | discord`. _(default `telegram`)_
- **`notify_locale`** — locale/style for logistics-group messages. _(optional; unset)_

### Expense + employer
- **`expense_receipt_inbox`** — address to forward business receipts to; setting it
  enables the expense path. _(optional; unset)_
- **`employer_definition_file`** — filename under `references/employers/` the
  assignment engine reads. _(optional; falls back to `default.md`)_
- **`assignment_type_codes`** — onsite/remote code map. _(optional; unset)_

> Secrets are **never** memory keys: `GMAIL_APP_PASSWORD` (env), `google_token.json` /
> `google_client_secret.json` (env bootstrap → `secrets/`), `secrets/loyalty_accounts.json`
> (chmod 600). Chat IDs and the email account live here on the volume, never in git.

## Delivery conventions

- **Silence is a feature.** A reconciliation cycle with nothing actionable →
  `[SILENT]`, no channel message.
- **Operator DM (`dm_chat_id`):** technical/infra only — decision gates, anomalies,
  integration failures. Never routine travel updates.
- **Logistics group (`travel_notify_chat_id`):** arrival-focused (flight numbers,
  routes, arrival times, status, links), adapted to `notify_locale` if set.
- **Raw URLs, never markdown links** in group messages (markdown crashes mobile clients).
- **Calendar event colors** (Google `colorId`, authoritative copy in
  `references/calendar-conventions.md`): flight = `9`, hotel = `2`, car = `6`,
  assignment = `10`.
- **Personal vs. onsite naming:** personal = `<destination city> <date>`; business =
  `Onsite: <code> <location>` only when `references/employers/` classifies the sender
  as business (default to personal when unknown).
- **Flight alerts:** home-airport arrivals within `alert_lead_hours` → one consolidated
  group alert `Flight# | Route | Date Arrival | Status | <raw URL>` — no repeat, no emoji.
- **Dedup:** calendar events matched on RFC822 Message-ID; same ID = update, not create.

## Current trips

_(none — captured as the principal reports them and as reconciliation cycles add them
to the calendar. Per entry: destination/context, ISO-8601 dates, status, companions,
bookings, notes.)_

## Active protocols

- Reconciliation: hourly email → parse → reconcile calendar → archive (`travel-reconciliation-hygiene`).
- Flight arrival alerts: hourly, home-airport only, disabled until `home_airport` +
  `travel_notify_chat_id` are set (`flight-arrival-alerts`).
- Weekly self-divergence audit: volume vs. git baseline, secrets-on-disk check
  (`self-divergence-audit`).

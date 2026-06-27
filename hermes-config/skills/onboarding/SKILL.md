---
name: onboarding
description: >
  First-run, principal-agnostic intake. Run on first contact (onboarding/state.json
  → onboarded:false) or whenever the configuration floor is missing — home base
  city/timezone, home airport, email account + backend, notification channels,
  calendar id. Collects the principal profile, email/channel setup, and optional
  employer definitions, expense routing, and loyalty accounts; writes them to ROOT
  memory (USER.md / MEMORY.md) + secrets; flips the onboarding gate to onboarded:true.
  This is the durable, single-principal replacement for any fleet/operator onboarding
  handshake. Trigger phrases: onboard me, set up my travel agent, start over,
  re-onboard, configure the configuration floor.
version: 1.0.0
tags: [onboarding, setup, profile, travel, principal-agnostic]
---

# Onboarding — make this deployment *someone's* travel agent

I ship principal-agnostic: a fresh volume has empty `USER.md` / `MEMORY.md` at the
home root and `onboarding/state.json` → `onboarded:false`. This skill turns the
generic deployment into one traveler's travel-operations agent. It is the
activation gate from AGENTS.md §1.1: **until the configuration floor (home base
city/timezone, home airport, email account + backend, notification channels,
calendar id) is written to `MEMORY.md`, I am provisional** — I answer travel
questions and retrieve reference data, but I do not engage the reconciliation
workflow. Fail closed.

The memory keys captured here are the contract that `cron/jobs.json`, the
`references/` cards, and the travel skills all read by name. Spell them exactly as
listed in `MEMORY.md` — the cron prompts and reference docs use byte-identical keys.

## When to Use

- **First contact:** `onboarding/state.json` reads `onboarded:false` (or the file
  is the legacy `humanOnboarded` shape — treat that as un-onboarded and overwrite it).
- **Incomplete floor:** `MEMORY.md` lacks any required key (city, timezone, airport,
  email account/backend, calendar id, channels).
- **Reset:** the principal says "start over" / "re-onboard".
- If the floor is already complete, this skill is overhead — say so and proceed to
  the normal decision cycle (AGENTS.md §4) instead.

## How to Run (conversational, one thing at a time)

Honor the simplicity doctrine: ask in small, friendly steps — never a giant form.
Confirm before each write. Skip anything the principal declines; only the
configuration floor is required to leave provisional status. Use generic placeholders
in examples — do not assume the principal's home, employer, or language.

### 1. Configuration floor (REQUIRED)

Ask one at a time, then write each to `MEMORY.md` under the named key:

- **`home_city`** — home base city (e.g. Chicago, London).
- **`home_timezone`** — IANA timezone (e.g. `America/Chicago`, `Europe/London`);
  fall back to `UTC` if unknown.
- **`home_airport`** — IATA code (e.g. ORD, LHR). This gates flight-arrival alerts;
  alerts fire only for flights arriving here. Leave `null` to disable alerts.
- **`travel_email_account`** — the inbox scanned for booking confirmations and
  receipts. Confirm the address after backend setup (`gmail getProfile` on the
  google_api path).
- **`travel_email_backend`** — how I reach that mailbox. Two supported paths:
  - **`himalaya`** — email-only. Gmail App Password in env (`GMAIL_APP_PASSWORD`);
    **no Google Cloud project**. Good for scanning confirmations and forwarding
    receipts when calendar reconciliation isn't needed.
  - **`google_api`** — Gmail **and** Google Calendar via GCP OAuth. Tokens are
    bootstrapped from env (`HERMES_GOOGLE_TOKEN_BOOTSTRAP` /
    `HERMES_GOOGLE_CLIENT_SECRET_BOOTSTRAP`) into `secrets/`; the wrapper is
    `/data/hermes/skills/productivity/google-workspace/scripts/google_api.py`.
    Required for calendar reconciliation. Most principals choose this; `himalaya`
    suits an email-only deployment. Never collect a password or token in chat —
    they come from the environment/bootstrap.
- **`travel_bookings_label`** — Gmail label for archived confirmations
  (default `Provider Bookings`).
- **`travel_calendar_id`** — Google Calendar reconciled to (default `primary`;
  confirm via `calendar list` on the google_api path).
- **Notification channels:**
  - **`dm_chat_id`** — operator DM (numeric). Technical/infra only: decision gates,
    anomalies, onboarding confirmations. Never routine travel updates (AGENTS.md §7).
  - **`travel_notify_chat_id`** — logistics group (numeric). Arrival-focused alerts
    for the travel party. Leave unset to disable group delivery.
  - **`travel_notify_channel`** — transport `telegram | slack | discord`
    (default `telegram`).
  - **`notify_locale`** *(optional)* — a non-English communication style the travel
    party prefers; I adapt tone in the logistics group only.
- **`alert_lead_hours`** — hours before a home-airport arrival to alert (default 48).

### 2. Principal profile → `USER.md`

- **Name(s)** and any regular travel companions (partner, family, colleague).
- **Travel patterns:** business / personal / mixed; typical cadence and destinations.
- **Preferences:** alert sensitivity (home-airport only, or all flights), preferred
  carriers / hotel chains / car vendors, calendar-naming style.

### 3. Optional: employer / onsite definitions

If the principal travels for business, define employer rules so the
employer-assignment engine can classify business trips:

- `mkdir -p $HERMES_HOME/references/employers` and write a modular definition file
  (codes, sender domains, onsite-detection rules, business-hour rules). See
  `references/employers/template.md` for the shape.
- **`employer_definition_file`** *(optional)* — the filename under
  `references/employers/` the engine reads (e.g. `example-corp.md`); falls back to
  `default.md` when unset.
- **`assignment_type_codes`** *(optional)* — onsite/remote code map.
- **`travel_assignments_label`** *(optional)* — Gmail label for assignment emails.

Skip this section entirely for personal-only travel.

### 4. Optional: expense forwarding

- **`expense_receipt_inbox`** *(optional)* — address to forward business rental-car /
  receipt emails to. Setting it enables the expense path (`integrations.yaml`
  `expense.enabled` and the reconciliation job's forward step); leave unset to keep
  expense forwarding off.

### 5. Optional: loyalty programs

- Collect account numbers + program names only if the principal wants tracking. Store
  them in `secrets/loyalty_accounts.json` (chmod 600) — **never** a memory key, never
  echoed back, never git. Skip if not interested.

## Writes (the learning actions, CoALA §4.5)

- **`USER.md`** (home root) — principal profile from §2. Replace the seed placeholder.
- **`MEMORY.md`** (home root) — the configuration floor (§1) under the named keys, plus
  the delivery conventions already documented in the template (raw-URL-never-markdown,
  ISO-8601+TZ, RFC822 dedup, silence doctrine, DM-vs-group boundaries). Replace the seed.
- **`references/employers/<file>.md`** *(optional)* — the employer definition from §3.
- **`secrets/loyalty_accounts.json`** *(optional, chmod 600)* — loyalty accounts from §5.
- **`onboarding/state.json`** — overwrite **wholesale** to the canonical onboarded
  shape (this also canonicalizes a legacy `humanOnboarded` volume):
  ```json
  {
    "onboarded": true,
    "profileComplete": true,
    "configurationFloorComplete": true,
    "agentId": "<preserve the existing value>",
    "firstContactAt": "<preserve, or set to now on first contact>",
    "onboardedAt": "<now, ISO-8601>"
  }
  ```
  This lifts provisional status. The gate reader fails closed: anything other than
  `onboarded:true` is treated as provisional.

## After Onboarding

Confirm the profile back in one short summary, restate the channel boundaries
("operator DM for decisions, the group for arrivals"), confirm the home-airport
filter and alert lead, and offer a next action: "Ready to scan for current
bookings?" From here the normal decision cycle (AGENTS.md §4) applies and the
reconciliation workflow has everything it needs.

## Privacy

- Email addresses and channel IDs are sensitive but **not secrets**: they live in
  `MEMORY.md` on the volume — never git, never `secrets/`.
- Loyalty numbers go to `secrets/loyalty_accounts.json` (chmod 600, never git, never echoed).
- OAuth tokens, App Passwords, and API keys are **never captured in chat** — they come
  from the environment or secure bootstrap (§1 `travel_email_backend`).

## Pitfalls

- **Treating provisional as a soft suggestion.** Until the floor is in `MEMORY.md`,
  do not run reconciliation — fail closed (AGENTS.md §1.1).
- **Drifting key names.** The cron jobs and reference docs read keys by exact spelling;
  a renamed key silently breaks reconciliation. Mirror `MEMORY.md` verbatim.
- **Capturing a secret as a memory key.** Passwords/tokens never enter `MEMORY.md` or
  git — env/bootstrap only.
- **Assuming Gmail/Calendar.** Ask for `travel_email_backend`; `himalaya` principals
  have no GCP project and no calendar.
- **Posting to the wrong channel.** Onboarding confirmations go to the operator DM,
  never the logistics group.

## Verification

- `onboarding/state.json` reads `onboarded:true` after completion.
- `MEMORY.md` contains every required floor key with a real value (or explicit `null`
  for the optional ones the principal declined).
- A re-run with a complete floor reports "already onboarded" and does no writes.
- No secret (password, token) appears in `MEMORY.md`, `USER.md`, or any git-tracked file.

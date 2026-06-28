---
name: parsing-provider-booking-united
description: >
  Parse United Airlines confirmation and rebooking emails into StandardBooking JSON.
  Handles multi-segment itineraries and schedule changes. Use when processing United
  flight confirmations or rebookings.
version: 1.0.0
tags: [travel, parsing, flight, united]
---

# Parsing United Airlines Bookings

Parse United Airlines itinerary emails into StandardBooking JSON
(`references/standard-booking-schema.md`) and hand each entry to `managing-calendar-travel`
for silent reconciliation. Sender/subject recognition is in
`references/provider-patterns.md` (United); Gmail mechanics are in
`references/gmail-ops.md`.

## When to Use

- An unprocessed United email (senders/subjects per `references/provider-patterns.md`)
  needs to become calendar events.
- Not for post-travel receipts (see `parsing-provider-receipt-united`).

## Procedure

1. **Find** unprocessed United mail with a Gmail search built from
   `references/provider-patterns.md` (sender `*@united.com`, excluding
   `-label:<travel_bookings_label>`) using the `google_api.py gmail search` contract in
   `references/gmail-ops.md` (the query is positional). Read full messages with `gmail get`.
2. **Parse** one StandardBooking per flight segment (a connection = multiple entries
   sharing the confirmation code):
   - `type: flight`, `source: united`.
   - `summary`: `✈️ UA<number> <ORIG>→<DEST>` (emoji + route; see the schema/calendar refs).
   - `start` = departure (origin local), `end` = arrival (destination local), each ISO 8601
     **with a timezone offset**.
   - `location` = departure airport name + code.
   - Record the source email's RFC 822 `Message-ID` for dedup.
3. **Rebooking:** same confirmation + a different flight number, or a "rebooked / schedule
   change / flight change" subject → `isRebooking: true`; set `oldFlightNumber` if visible.
4. **Loyalty (optional):** if `secrets/loyalty_accounts.json` has a `united` entry, set
   `loyaltyNumber` (`references/loyalty-registry.md`) — never echo or log it.
5. **Hand off** each StandardBooking to `managing-calendar-travel`. Reconciliation is
   `[SILENT]`; this skill sends no notifications.

United emails are HTML-heavy — extract structured fields only; never pass raw HTML into a
shell argument.

## Pitfalls

- Always include timezone offsets (a missing offset fails calendar create).
- Validate the confirmation code (`^[A-Z0-9]{6,10}$`) and flight number (`^UA\d{1,5}$`)
  before use; quote all values passed to `google_api.py`; never interpolate raw email body
  content into a command.
- Fail closed on an unrecognized sender/format: skip rather than emit a wrong `source`.

## Verification

- One StandardBooking per segment; valid `source` enum; ISO-8601+offset times; raw URLs.
- A re-scan after labeling produces no new bookings.

## Anomalies

Escalate to `dm_chat_id` only on a repeated unrecoverable parse/API failure — never routine activity.

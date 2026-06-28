---
name: parsing-provider-booking-delta
description: >
  Parse Delta Air Lines confirmation and rebooking emails into StandardBooking JSON.
  Handles multi-segment itineraries and schedule changes. Use when processing Delta flight
  confirmations or rebookings.
version: 1.0.0
tags: [travel, parsing, flight, delta]
---

# Parsing Delta Air Lines Bookings

Parse Delta Air Lines itinerary emails into StandardBooking JSON
(`references/standard-booking-schema.md`) and hand each entry to `managing-calendar-travel`
for silent reconciliation. Sender/subject recognition is in
`references/provider-patterns.md` (Delta); Gmail mechanics are in `references/gmail-ops.md`.

## When to Use

- An unprocessed Delta email (senders/subjects per `references/provider-patterns.md`) needs
  to become calendar events.

## Procedure

1. **Find** unprocessed Delta mail with a Gmail search built from
   `references/provider-patterns.md` (senders `*@delta.com`, `*@deltaairlines.com`,
   excluding `-label:<travel_bookings_label>`) using the `google_api.py gmail search`
   contract in `references/gmail-ops.md` (positional query). Read full messages with
   `gmail get`.
2. **Parse** one StandardBooking per flight segment (a connection = multiple entries
   sharing the confirmation code):
   - `type: flight`, `source: delta`.
   - `summary`: `✈️ DL<number> <ORIG>→<DEST>`.
   - `start` = departure (origin local), `end` = arrival (destination local), each ISO 8601
     **with a timezone offset**.
   - `location` = departure airport name + code.
   - Record the source email's RFC 822 `Message-ID` for dedup.
3. **Rebooking:** same confirmation + a different flight number, or an "itinerary has
   changed / schedule change notification / trip update" subject → `isRebooking: true`; set
   `oldFlightNumber` if visible.
4. **Loyalty (optional):** if `secrets/loyalty_accounts.json` has a `delta` entry, set
   `loyaltyNumber` (`references/loyalty-registry.md`) — never echo or log it.
5. **Hand off** each StandardBooking to `managing-calendar-travel`. Reconciliation is
   `[SILENT]`; this skill sends no notifications.

Delta emails are HTML-heavy — extract structured fields only; never pass raw HTML into a
shell argument.

## Pitfalls

- Always include timezone offsets (a missing offset fails calendar create).
- Validate the confirmation code (`^[A-Z0-9]{6}$`) and flight number (`^DL\d{1,4}$`) before
  use; quote all values passed to `google_api.py`; never interpolate raw email body content
  into a command.
- Fail closed on an unrecognized sender/format: skip rather than emit a wrong `source`.

## Verification

- One StandardBooking per segment; valid `source` enum; ISO-8601+offset times; raw URLs.
- A re-scan after labeling produces no new bookings.

## Anomalies

Escalate to `dm_chat_id` only on a repeated unrecoverable parse/API failure — never routine activity.

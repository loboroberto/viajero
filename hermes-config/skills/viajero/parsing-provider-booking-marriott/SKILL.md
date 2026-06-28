---
name: parsing-provider-booking-marriott
description: >
  Parse Marriott (Bonvoy) hotel reservation emails into StandardBooking JSON. Handles
  check-in/check-out times and reservation modifications. Use when processing Marriott
  booking confirmations or stay details.
version: 1.0.0
tags: [travel, parsing, hotel, marriott]
---

# Parsing Marriott Hotel Bookings

Parse Marriott / Bonvoy reservation emails into StandardBooking JSON
(`references/standard-booking-schema.md`) and hand each entry to `managing-calendar-travel`
for silent reconciliation. Sender/subject recognition is in
`references/provider-patterns.md` (Marriott); Gmail mechanics are in
`references/gmail-ops.md`.

## When to Use

- An unprocessed Marriott email (senders/subjects per `references/provider-patterns.md`)
  needs to become a calendar event.

## Procedure

1. **Find** unprocessed Marriott mail with a Gmail search built from
   `references/provider-patterns.md` (senders `*@marriott.com`, `*@bonvoy.marriott.com`,
   excluding `-label:<travel_bookings_label>`) via the `google_api.py gmail search` contract
   in `references/gmail-ops.md` (positional query). Read the full message with `gmail get`;
   to confirm a single message by id use `gmail search "rfc822msgid:<id>"`.
2. **Parse** one StandardBooking per reservation (separate confirmation numbers = separate
   bookings):
   - `type: hotel`, `source: marriott`.
   - `summary`: `🏨 <Property> — <City>`.
   - `start` = check-in (default `15:00` local if unspecified), `end` = check-out (default
     `11:00` local), each ISO 8601 **with a timezone offset**.
   - `location` = hotel street address.
   - Record the source email's RFC 822 `Message-ID` for dedup.
3. **Modification:** same confirmation + changed dates/property, or a "reservation
   modification / updated confirmation / change to your reservation" subject →
   `isRebooking: true` (`oldFlightNumber` stays `null` — N/A for hotels).
4. **Loyalty (optional):** if `secrets/loyalty_accounts.json` has a `marriott` entry, set
   `loyaltyNumber` and optionally note it in the description
   (`references/loyalty-registry.md`) — never echo or log it.
5. **Hand off** each StandardBooking to `managing-calendar-travel`. Reconciliation is
   `[SILENT]`; this skill sends no notifications.

Marriott emails are HTML-heavy — extract structured fields only; never pass raw HTML into a
shell argument.

## Pitfalls

- Always include timezone offsets (a missing offset fails calendar create).
- Validate the confirmation code (`^[A-Z0-9]{4,10}$`); quote all values passed to
  `google_api.py`; never interpolate raw email body content into a command.
- Loyalty numbers are secrets — read at parse time from `secrets/loyalty_accounts.json`,
  never from a memory key, and never write one back.

## Verification

- One StandardBooking per reservation; valid `source` enum; ISO-8601+offset times; raw URLs.
- A re-scan after labeling produces no new bookings.

## Anomalies

Escalate to `dm_chat_id` only on a repeated unrecoverable parse/API failure — never routine activity.

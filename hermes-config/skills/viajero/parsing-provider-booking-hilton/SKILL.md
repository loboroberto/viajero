---
name: parsing-provider-booking-hilton
description: >
  Parse Hilton (Honors) hotel reservation emails into StandardBooking JSON. Status: Stub —
  recognition and output shape are defined; extraction is not yet implemented. Use when
  processing Hilton booking confirmations or upcoming-stay reminders.
version: 1.0.0
tags: [travel, parsing, hotel, hilton, stub]
---

# Parsing Hilton Hotel Bookings

> **Status: Stub** — sender/subject recognition and the target output are specified below;
> the extraction logic is not yet implemented (a later issue completes it).

Parse Hilton reservation emails into StandardBooking JSON
(`references/standard-booking-schema.md`) and hand each to `managing-calendar-travel`.
Recognition is in `references/provider-patterns.md` (Hilton); Gmail mechanics in
`references/gmail-ops.md`.

## When to Use

- An unprocessed Hilton email needs to become a calendar event.

## Procedure (outline — not yet implemented)

1. Find unprocessed Hilton mail per `references/provider-patterns.md` (`*@hilton.com`,
   `*@hiltonhonors.com`), using the positional Gmail query in `references/gmail-ops.md`.
2. Emit one StandardBooking per reservation: `type: hotel`, `source: hilton`, `summary`
   `🏨 <Property> — <City>`, check-in `start` (default `15:00` local) / check-out `end`
   (default `11:00` local) ISO 8601 **with offsets** (infer the zone from the property
   location — `references/airports-timezones.md` / `home_timezone` as a last resort),
   street-address `location`; record the source RFC 822 `Message-ID`.
3. **Loyalty (optional):** if `secrets/loyalty_accounts.json` has a `hilton` entry, set
   `loyaltyNumber` (`references/loyalty-registry.md`) — never echo, log, or store it in a
   memory key.
4. Hand off to `managing-calendar-travel`. Reconciliation is `[SILENT]`; no notifications.

## Pitfalls

- Include timezone offsets; fail closed on an unrecognized format; quote all values passed
  to `google_api.py`.

## Verification

- When implemented: one StandardBooking per reservation, valid `source` enum, no duplicate
  on re-scan.

## Anomalies

Escalate to `dm_chat_id` only on a repeated unrecoverable failure — never routine activity.

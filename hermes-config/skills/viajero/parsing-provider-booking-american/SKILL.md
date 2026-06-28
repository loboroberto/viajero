---
name: parsing-provider-booking-american
description: >
  Parse American Airlines confirmation and rebooking emails into StandardBooking JSON.
  Status: Stub — recognition and output shape are defined; extraction is not yet
  implemented. Use when processing American Airlines flight confirmations.
version: 1.0.0
tags: [travel, parsing, flight, american, stub]
---

# Parsing American Airlines Bookings

> **Status: Stub** — sender/subject recognition and the target output are specified below;
> the extraction logic is not yet implemented (a later issue completes it).

Parse American Airlines itinerary emails into StandardBooking JSON
(`references/standard-booking-schema.md`) and hand each to `managing-calendar-travel`.
Recognition is in `references/provider-patterns.md` (American); Gmail mechanics in
`references/gmail-ops.md`.

## When to Use

- An unprocessed American Airlines email needs to become calendar events.

## Procedure (outline — not yet implemented)

1. Find unprocessed American mail per `references/provider-patterns.md` (`*@aa.com`,
   `*@americanairlines.com`), using the positional Gmail query in `references/gmail-ops.md`.
2. Emit one StandardBooking per flight segment: `type: flight`, `source: american`,
   `summary` `✈️ AA<number> <ORIG>→<DEST>`, ISO 8601 `start`/`end` **with offsets**,
   departure `location`; record the source RFC 822 `Message-ID`.
3. Detect rebookings (same confirmation + new flight number, or a schedule-change subject).
4. Hand off to `managing-calendar-travel`. Reconciliation is `[SILENT]`; no notifications.

## Pitfalls

- Include timezone offsets; fail closed on an unrecognized format (skip rather than emit a
  wrong `source`); quote all values passed to `google_api.py`.

## Verification

- When implemented: one StandardBooking per segment, valid `source` enum, no duplicate on
  re-scan.

## Anomalies

Escalate to `dm_chat_id` only on a repeated unrecoverable failure — never routine activity.

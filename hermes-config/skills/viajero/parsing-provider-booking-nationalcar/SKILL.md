---
name: parsing-provider-booking-nationalcar
description: >
  Parse National Car Rental / Enterprise reservation emails into StandardBooking JSON.
  Status: Stub — recognition and output shape are defined; extraction is not yet
  implemented. Use when processing car-rental confirmation or pickup-reminder emails.
version: 1.0.0
tags: [travel, parsing, car, nationalcar, stub]
---

# Parsing National Car Rental Bookings

> **Status: Stub** — sender/subject recognition and the target output are specified below;
> the extraction logic is not yet implemented (a later issue completes it).

Parse National Car Rental / Enterprise (same parent company) reservation emails into
StandardBooking JSON (`references/standard-booking-schema.md`) and hand each to
`managing-calendar-travel`. Recognition is in `references/provider-patterns.md` (National
Car Rental); Gmail mechanics in `references/gmail-ops.md`.

## When to Use

- An unprocessed car-rental email needs to become a calendar event.

## Procedure (outline — not yet implemented)

1. Find unprocessed car-rental mail per `references/provider-patterns.md` (`*@nationalcar.com`),
   using the positional Gmail query in `references/gmail-ops.md`.
2. Emit one StandardBooking per rental: `type: car`, `source: nationalcar`, `summary`
   `🚗 National Car Rental <pickup code>`, pickup `start` / return `end` ISO 8601 **with
   offsets**, pickup-location `location`; record the source RFC 822 `Message-ID`.
3. Hand off to `managing-calendar-travel`. Reconciliation is `[SILENT]`; no notifications.

## Expense forwarding

A rental receipt/invoice is forwarded **only** under the expense gate — `integrations.yaml`
`expense.enabled: true` *and* the `expense_receipt_inbox` memory key set *and* the booking
categorized `business-travel`. Mechanism and fail-closed rules are in
`references/expense-forwarding.md`. Never hard-code a destination address.

## Pitfalls

- Include timezone offsets; fail closed on an unrecognized format; quote all values passed
  to `google_api.py`.
- When uncertain whether a receipt is business vs personal, do **not** forward (fail closed).

## Verification

- When implemented: one StandardBooking per rental; valid `source` enum; receipts forwarded
  only when the expense gate holds; no duplicate on re-scan.

## Anomalies

Escalate to `dm_chat_id` only on a repeated unrecoverable failure — never routine activity.

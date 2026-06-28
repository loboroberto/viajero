---
name: parsing-provider-receipt-united
description: >
  Parse United Airlines post-travel receipt emails into expense data (final total, payment
  method, travel dates). Status: Stub — recognition and output shape are defined; extraction
  is not yet implemented. Use when processing United receipt emails for expense tracking.
version: 1.0.0
tags: [travel, parsing, receipt, expense, united, stub]
---

# Parsing United Receipts

> **Status: Stub** — sender/subject recognition and the target output are specified below;
> the extraction logic is not yet implemented (a later issue completes it).

Parse United Airlines receipt emails (sent after travel) into expense data and hand it to
`tracking-expense-travel`. This is the **expense** path — distinct from booking parsing
(`parsing-provider-booking-united`). Recognition is in `references/provider-patterns.md`
(United); Gmail mechanics in `references/gmail-ops.md`; forwarding rules in
`references/expense-forwarding.md`.

## When to Use

- An unprocessed United receipt email (subjects like "Your receipt", "E-receipt for your
  trip") needs to become expense data.

## Procedure (outline — not yet implemented)

1. Find unprocessed United receipts per `references/provider-patterns.md` (`*@united.com`),
   using the positional Gmail query in `references/gmail-ops.md`.
2. Extract expense fields: confirmation number, flight number + route, final amount paid,
   payment method, travel date; record the source RFC 822 `Message-ID`.
3. Hand the expense data to `tracking-expense-travel`. If expense forwarding is enabled and
   the trip is business, forward per `references/expense-forwarding.md`.

This skill reconciles silently and emits no notifications.

## Pitfalls

- Fail closed on an unrecognized format; quote all values passed to `google_api.py`.
- Forward a receipt only under the expense gate (`references/expense-forwarding.md`); when
  business-vs-personal is uncertain, do not forward.

## Verification

- When implemented: expense fields extracted; forwarding only when the gate holds; no
  double-processing on re-scan.

## Anomalies

Escalate to `dm_chat_id` only on a repeated unrecoverable failure — never routine activity.

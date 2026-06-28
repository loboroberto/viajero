---
name: tracking-expense-travel
description: >
  Aggregate travel expenses per trip from parsed receipts and bookings for reporting.
  Status: Stub — inputs, categories, and output shape are defined; aggregation is not yet
  implemented. Use when summarizing travel costs for a trip.
version: 1.0.0
tags: [travel, expense, reporting, stub]
---

# Tracking Travel Expenses

> **Status: Stub** — inputs, categories, and the output shape are specified below;
> aggregation is not yet implemented (a later issue completes it).

Aggregate travel expenses for a trip from already-parsed sources. This skill **aggregates
only** — it does not parse emails (the parser/receipt skills do) and it does not forward
receipts (that is the expense gate in `references/expense-forwarding.md`). Bookings follow
`references/standard-booking-schema.md`.

## When to Use

- Expense data from `parsing-provider-receipt-united` (and future receipt parsers) needs to
  be totaled into a per-trip report.

## Inputs

- Flight/hotel/car receipts and out-of-pocket items already extracted by other skills.

## Categories

Flights · Hotels · Car rentals · Meals · Ground transport · Miscellaneous.

## Output (shape)

A per-trip report: trip identifier (derived from the trip dates), total per category, grand
total, currency (normalized to a single reporting currency).

## Procedure (outline — not yet implemented)

1. Collect the trip's expense items (grouped by the booking dates / confirmation set).
2. Bucket each into a category and sum; produce the per-trip report.

This skill reconciles silently and emits no notifications.

## Pitfalls

- Aggregate only — do not re-parse emails or forward receipts here.
- Gate any forwarding behavior elsewhere on `expense.enabled` + `expense_receipt_inbox`
  (`references/expense-forwarding.md`).

## Verification

- When implemented: category totals sum to the grand total; one report per trip.

## Anomalies

Escalate to `dm_chat_id` only on a repeated unrecoverable failure — never routine activity.

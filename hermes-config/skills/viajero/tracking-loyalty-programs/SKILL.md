---
name: tracking-loyalty-programs
description: >
  Look up the principal's loyalty-program numbers (by provider) so parsers can attach the
  loyaltyNumber field to a StandardBooking. Status: Stub — the storage contract and lookup
  are defined; not yet implemented. Use when a booking needs its loyalty number.
version: 1.0.0
tags: [travel, loyalty, secrets, stub]
---

# Tracking Loyalty Programs

> **Status: Stub** — the storage contract and lookup flow are specified below; the
> implementation is deferred (a later issue completes it).

Provide the right loyalty number for a provider so a parser can set the `loyaltyNumber`
field (`references/standard-booking-schema.md`). Loyalty numbers are **secrets** — the full
storage contract is in `references/loyalty-registry.md`.

## When to Use

- A parser has identified a booking's `source` and needs the matching loyalty number.

## Storage contract

Loyalty numbers live in `secrets/loyalty_accounts.json` (`chmod 600`, volume-only, never a
memory key, never git), a flat object keyed by the StandardBooking `source`
(`united`, `delta`, `american`, `marriott`, `hilton`, `nationalcar`) — see
`references/loyalty-registry.md`.

## Procedure (outline — not yet implemented)

1. Read `secrets/loyalty_accounts.json`.
2. Look up the booking's `source`.
3. If present, return the number for the parser to set `loyaltyNumber`; if absent, return
   nothing (the field is optional — fail closed).

## Pitfalls

- Never read loyalty numbers from a memory key, never write one back to memory, never log or
  echo a number into a calendar title or message.
- Keys are the `source` enum values — not brand/program names.

## Verification

- When implemented: a present `source` returns its number; a missing one returns nothing
  (no error, no guess); no number ever appears in memory, logs, or git.

## Anomalies

Escalate to `dm_chat_id` only on a repeated unrecoverable failure — never routine activity.

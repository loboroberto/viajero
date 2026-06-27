# Expense Forwarding

> **Durable, user-agnostic reference.** Conventions only. The receipt inbox is a
> per-principal memory key (`expense_receipt_inbox`), referenced by name, never by
> value, and feature-gated; no operator address appears here.

How the agent forwards **business-travel** receipts to the principal's expense system.
Mechanics use Gmail send (see [gmail-ops.md](gmail-ops.md)); categorization follows
[provider-patterns.md](provider-patterns.md) and
[calendar-conventions.md](calendar-conventions.md).

## Gate

Forwarding runs only when **both** hold:

1. `integrations.yaml` `expense.enabled: true`, and
2. the `expense_receipt_inbox` memory key is set (the destination address).

If either is missing, do nothing (a fresh deployment ships with expense disabled).

## Trigger

After a booking is reconciled to the calendar, examine the source email. Forward when:

- the email carries an **itemized receipt / invoice** (e.g. a car-rental final
  receipt, a hotel folio), **and**
- the booking is categorized `business-travel` (a concurrent work assignment, or
  arrival via the employer's corporate TMC). **Skip `personal-travel`** receipts.

When uncertain about business-vs-personal, do **not** forward (fail closed — a missed
forward is recoverable; a personal receipt sent to an employer inbox is not).

## Forwarding rules

- **Forward once.** Track forwarded receipts (by RFC 822 `Message-ID`, the same dedup
  key used for calendar reconciliation) so a re-scanned inbox never double-forwards.
- **Preserve the original.** Forward with attachments intact (the PDF/invoice is what
  the expense system ingests); keep the original subject, prefixed for clarity if
  helpful (e.g. `Fwd: <original subject>`).
- **Body:** include the confirmation number and the trip dates so the receipt is
  self-describing; raw URLs only (no markdown).
- **After forwarding:** apply the processed label (`travel_bookings_label`) and
  archive, consistent with the booking reconciliation flow.

## Mechanism

```bash
python3 /data/hermes/skills/productivity/google-workspace/scripts/google_api.py \
  gmail send --to "<expense_receipt_inbox>" --subject "Fwd: <original subject>" --body "<receipt summary + raw URLs>"
```

For receipts whose value is in the attachment, forward the original message so the
attachment travels with it (rather than composing a fresh body-only mail).

## Privacy

The destination inbox is operational, not secret, and lives in `MEMORY.md`
(`expense_receipt_inbox`) on the volume — never in git. Receipts may contain personal
financial detail: forward only to the configured inbox, only for business travel.

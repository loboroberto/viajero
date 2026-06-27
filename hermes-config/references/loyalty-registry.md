# Loyalty Registry

> **Durable, user-agnostic reference.** Conventions + storage contract only. Loyalty
> numbers are **secrets** — none appear here, in any memory key, or in git.

How loyalty-program numbers are organized and securely stored so a parser can attach
the `loyaltyNumber` field (see [standard-booking-schema.md](standard-booking-schema.md))
without ever writing the number to memory or git.

## Program taxonomy

| Class | Examples of program type | Matching `source` |
|-------|--------------------------|-------------------|
| Airline frequent-flyer | airline mileage programs | `united`, `delta`, `american` |
| Hotel loyalty | hotel chain rewards | `marriott`, `hilton` |
| Car-rental loyalty | rental membership | `nationalcar` |

Keys align to the StandardBooking `source` values (see
[provider-patterns.md](provider-patterns.md)) so a parser can look up the right
number by the provider it already identified.

## Storage contract

Loyalty numbers live in a single secrets file on the volume, **never** in `MEMORY.md`,
**never** in git:

- **Path:** `secrets/loyalty_accounts.json` (under the agent home; `secrets/` is
  `chmod 700`, the file `chmod 600`).
- **Origin:** captured at onboarding (or placed via bootstrap); like other secrets it
  is gitignored and machine-local.
- **Shape:** a flat object keyed by `source`:

```json
{
  "united": "<number>",
  "marriott": "<number>",
  "nationalcar": "<number>"
}
```

Only include programs the principal actually has; omit the rest.

## Parser usage

When a parser emits a StandardBooking and the principal has a matching program:

1. Read `secrets/loyalty_accounts.json`.
2. Look up the booking's `source`.
3. If present, set `loyaltyNumber` to that value (and optionally note it in the
   `description`).

If the file is absent or the `source` has no entry, leave `loyaltyNumber` unset — it
is optional. Never log the number, never echo it into a calendar event title, and
never write it back to a memory key.

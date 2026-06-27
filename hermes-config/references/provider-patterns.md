# Provider Email Patterns

> **Durable, user-agnostic reference.** Public sender/subject conventions only — no
> traveler data. The principal's processed-label name, account, and any
> employer-specific travel-platform domain live in `MEMORY.md` /
> `references/employers/<name>.md`, never here.

Canonical sender and subject patterns per travel provider, used by parser skills to
build Gmail search queries and validate senders before emitting a
[StandardBooking](standard-booking-schema.md). For the Gmail API mechanics see
[gmail-ops.md](gmail-ops.md).

## Gmail search query format

Parser skills pass the query as a **positional argument** (there is no `--query`
flag) and exclude the already-processed label (the label name is the
`travel_bookings_label` memory key):

```bash
python3 /data/hermes/skills/productivity/google-workspace/scripts/google_api.py \
  gmail search "from:(*@united.com) -label:<travel_bookings_label>" --max 5
```

## Provider registry

### United Airlines
- **Sender:** any `*@united.com`
- **Subjects:** "Your United flight confirmation", "Confirmation - …", "Your flight itinerary", "Schedule change", "We've rebooked your flight"
- **Search:** `from:(*@united.com) -label:<travel_bookings_label>`
- **Confirmation code:** `^[A-Z0-9]{6,10}$` · **Flight number:** `^UA\d{1,5}$`

### Delta Air Lines
- **Sender:** any `*@delta.com`, `*@deltaairlines.com`
- **Subjects:** "Your trip confirmation", "E-receipt for your trip", "Schedule change notification", "Your trip update", "Your itinerary has changed"
- **Search:** `from:(*@delta.com OR *@deltaairlines.com) -label:<travel_bookings_label>`
- **Confirmation code:** `^[A-Z0-9]{6}$` · **Flight number:** `^DL\d{1,4}$`

### American Airlines
- **Sender:** any `*@aa.com`, `*@americanairlines.com`
- **Subjects:** "Your flight confirmation", "Confirmation - …", "Your itinerary", "Schedule change"
- **Search:** `from:(*@aa.com OR *@americanairlines.com) -label:<travel_bookings_label>`
- **Confirmation code:** `^[A-Z0-9]{6}$` (typical) · **Flight number:** `^AA\d{1,5}$`

### Marriott Hotels
- **Sender:** any `*@marriott.com`, `*@bonvoy.marriott.com`
- **Subjects:** "Reservation confirmation", "Your upcoming stay", "Itinerary for your stay", "Reservation modification"
- **Search:** `from:(*@marriott.com OR *@bonvoy.marriott.com) -label:<travel_bookings_label>`
- **Confirmation code:** `^[A-Z0-9]{4,10}$` · **Identifiers:** property name, street address

### Hilton Hotels
- **Sender:** any `*@hilton.com`, `*@hiltonhonors.com`
- **Subjects:** "Reservation confirmation", "Your upcoming stay", "Check-in reminder", "Reservation update"
- **Search:** `from:(*@hilton.com OR *@hiltonhonors.com) -label:<travel_bookings_label>`
- **Confirmation code:** `^[A-Z0-9]{4,10}$` · **Identifiers:** property name, street address

### National Car Rental
- **Sender:** any `*@nationalcar.com`
- **Subjects:** "Reservation confirmation", "Your upcoming rental", "Rental agreement", "Confirmation - …"
- **Search:** `from:(*@nationalcar.com) -label:<travel_bookings_label>`
- **Confirmation code:** `^[A-Z0-9]{6,8}$` (varies) · **Identifier:** pickup location (city, airport code)

### Corporate Travel Management (TMC)
A corporate travel-management platform books flights, hotels, and cars under a single
itinerary on behalf of an employer. The platform and its sender domain are
**principal-specific** — different employers use different TMCs — so the sender
pattern is **not hard-coded here**: it is configured in the active employer
definition (`references/employers/<name>.md` `sender_patterns`) and surfaced via the
`employer_definition_file` memory key.
- **`source`:** `corporate-tmc`
- **Sender:** the employer's configured travel-platform domain (per the employer definition)
- **Subjects (typical):** "Your trip to …", "Booking confirmation", "Itinerary for …", "Updated booking", "Cancellation confirmation"
- **Search:** `from:(<employer travel-platform domain>) -label:<travel_bookings_label>`
- **Scope:** bundles multiple segment types in one itinerary — the parser must **decompose** it into a separate StandardBooking per segment (flight / hotel / car).

## Personal vs. business categorization

Determine at parse time and record in StandardBooking `tags` (full rules in
[calendar-conventions.md](calendar-conventions.md)):

1. If a concurrent **work assignment** covers the same dates → `business-travel` (apply the `Onsite:` prefix only when the location differs from the principal's home base).
2. A booking arriving through the employer's corporate TMC → `business-travel`.
3. Otherwise (consumer OTA / personal card, no assignment) → `personal-travel` (no `Onsite:` prefix).
4. When uncertain, default to `personal-travel`.

## Reconciliation: multiple emails for one booking

- **Most recent wins.** For the same confirmation number with differing detail, apply in order: rebooking/"schedule change" emails override originals; amendments override originals; a cancellation triggers deletion of the calendar event.
- **Search before creating.** Check the calendar for an existing event with the same confirmation number first; emit an **update**, not a duplicate.

## Gmail search operator quick reference

| Operator | Example | Notes |
|----------|---------|-------|
| `from:` | `from:*@united.com` | sender domain |
| `to:` | `to:you@example.com` | recipient |
| `-label:` | `-label:<travel_bookings_label>` | exclude already-processed |
| `is:unread` | `is:unread` | unread only |
| `in:inbox` | `in:inbox` | inbox folder |
| `subject:` | `subject:confirmation` | subject contains |
| `has:attachment` | `has:attachment` | has PDF/attachment |
| `newer_than:` | `newer_than:7d` | recency window |
| `( )` | `(from:a OR from:b)` | grouping |
| `rfc822msgid:` | `rfc822msgid:<id>` | exact message (dedup) |

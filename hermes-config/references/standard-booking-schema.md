# Standard Booking Schema

> **Durable, user-agnostic reference.** This file defines a stable data *contract*,
> not a principal's data. It carries no traveler names, trips, account IDs, or
> secrets — those live in `MEMORY.md` (operational facts) and `secrets/` (tokens,
> loyalty numbers) on the volume, never here. Every example value below is
> fictional and illustrative.

Canonical JSON interchange format for all travel bookings (flights, hotels, car
rentals, work assignments). **Emitted** by every parser skill; **consumed** by
`managing-calendar-travel` for calendar event creation and lifecycle management.
See also: [provider-patterns.md](provider-patterns.md) (how each provider's email
is recognized), [calendar-conventions.md](calendar-conventions.md) (how a booking
becomes a calendar event), [gmail-ops.md](gmail-ops.md) (the API contract).

## Root Schema

```json
{
  "type": "flight|hotel|car|assignment",
  "source": "united|delta|american|marriott|hilton|nationalcar|corporate-tmc|work-assignment",
  "confirmationNumber": "string (required)",
  "summary": "string (required, emoji + text for calendar display)",
  "start": "ISO 8601 with timezone offset (required)",
  "end": "ISO 8601 with timezone offset (required)",
  "location": "string (required, airport/hotel/address for calendar location field)",
  "description": "string (optional, multi-line narrative, raw URLs never markdown)",
  "isRebooking": "boolean (default: false)",
  "oldFlightNumber": "string (null if not applicable)",
  "loyaltyNumber": "string (optional, resolved at parse time from secrets/loyalty_accounts.json)",
  "tags": "array of strings (optional, for filtering and retrieval)"
}
```

## Field Details

### `type`
- `"flight"` — airline boarding pass or confirmation
- `"hotel"` — lodging reservation (check-in / check-out)
- `"car"` — vehicle rental (pickup / return)
- `"assignment"` — employer work assignment (onsite / remote)

### `source`
Identifies the provider class. A parser skill MUST validate the sender against the
known patterns in [provider-patterns.md](provider-patterns.md) before emitting a
StandardBooking.

| Class | `source` value | Recognized via |
|-------|----------------|----------------|
| Airline | `united`, `delta`, `american` | public carrier sender domains |
| Hotel | `marriott`, `hilton` | public chain sender domains |
| Car rental | `nationalcar` | public rental-brand sender domains |
| Corporate travel | `corporate-tmc` | the employer's travel-management platform; the exact sender domain is per-principal — configured in `references/employers/<name>.md` `sender_patterns`, never hard-coded here |
| Work assignment | `work-assignment` | sender/code patterns from the active employer definition |

New airline/hotel/car parsers add their own `source` value; corporate-travel and
assignment senders are always principal-specific and resolved from the employer
definition, so they share the two generic values above.

### `confirmationNumber`
Opaque string used for deduplication; extracted verbatim from the source email.
Most providers match `^[A-Z0-9]{4,10}$` — validate per source (see provider-patterns.md).

### `summary`
Calendar event title. Emoji is **required**; use full names, not codes; show flight
route direction with an arrow `→`.

| Type | Example |
|------|---------|
| Flight | `✈️ UA875 ORD→LAX` |
| Hotel | `🏨 Grand Plaza Hotel — Chicago` |
| Car | `🚗 National Car Rental ORD` |
| Assignment (onsite) | `🏢 Onsite: New York` |
| Assignment (remote) | `🏢 Remote: <home city>` |

`Onsite:` / `Remote:` prefixing rules are in [calendar-conventions.md](calendar-conventions.md).

### `start` / `end`
Datetime in ISO 8601 **with timezone offset or `Z`** (a missing offset fails calendar
create — see gmail-ops.md pitfalls). Use local time at the event location.

```
"2026-03-07T14:30:00-06:00"   (CST, UTC-6)
"2026-03-07T09:15:00Z"         (UTC)
"2026-03-07T09:15:00+05:30"    (IST, UTC+5:30)
```

- **Flight:** `start` = departure (origin local), `end` = arrival (destination local).
- **Hotel:** `start` = check-in (default 15:00 if unspecified), `end` = check-out (default 11:00).
- **Assignment:** `start` = first business day 09:00, `end` = last business day 17:00 (unless the employer definition specifies other `business_hours`).

### `location`
The primary venue, as a human-readable string for the calendar location field.

- Flight: `"Chicago O'Hare International Airport (ORD)"`
- Hotel: `"<street address or property name>"`
- Car: `"Chicago O'Hare (ORD)"` (pickup)
- Assignment: office name/address from the employer definition, or the principal's home city for remote.

### `description`
Freeform, multi-line. **Raw URLs only — never markdown links** (mobile calendar
clients render markdown links poorly or crash; see calendar-conventions.md). Use it for:
full itinerary detail (connecting legs, seats), booking/receipt references, the
confirmation code, rebooking notes, and raw status/booking URLs.

### `isRebooking`
`true` only when the same confirmation number reappears with a different flight/hotel
number, or the subject signals a change ("rebooked", "schedule change", "modification").
When `true`, populate `oldFlightNumber` if the prior identifier is visible.

### `oldFlightNumber`
Previous flight/itinerary identifier on a detected rebooking; `null` otherwise (the
field exists for schema compliance even for hotel/car rebookings).

### `loyaltyNumber`
Optional. **Resolved at parse time by looking up the provider key in
`secrets/loyalty_accounts.json`** (chmod 600, volume-only) — see
[loyalty-registry.md](loyalty-registry.md). Loyalty numbers are secrets: they are
NEVER stored in a memory key, in this schema, or in git.

### `tags`
Optional strings for filtering/retrieval, e.g. `home-airport-leg`, `personal-travel`,
`business-travel`, `onsite`, `remote`, `multi-segment`, `travel-placeholder`.

## Calendar Event Mapping

When `managing-calendar-travel` creates an event from a StandardBooking:

| Field | Calendar field | Notes |
|-------|----------------|-------|
| `summary` | Event title | full emoji + text |
| `start` / `end` | Start / End | ISO 8601 with timezone |
| `location` | Location | venue name/address |
| `description` | Description | multi-line, raw URLs |
| `type` | Color (`colorId`) | flight→`9`, hotel→`2`, car→`6`, assignment→`10` |
| `confirmationNumber` | in description | appended for dedup/reference |

Color codes are authoritative in [calendar-conventions.md](calendar-conventions.md).

## Deduplication Key

Before creating an event, search for an existing one (see calendar-conventions.md),
matching in priority order:

1. RFC 822 `Message-ID` of the source email (`rfc822msgid:` search), when available
2. Confirmation number (in the event description)
3. Provider + flight/booking number (summary match)
4. Summary + start date (heuristic fallback)

If a match exists, **update** it rather than creating a duplicate.

## Example Payloads

### Flight confirmation
```json
{
  "type": "flight",
  "source": "united",
  "confirmationNumber": "ABC123",
  "summary": "✈️ UA875 ORD→LAX",
  "start": "2026-03-15T13:00:00-05:00",
  "end": "2026-03-15T15:30:00-07:00",
  "location": "Chicago O'Hare International Airport (ORD)",
  "description": "Confirmation: ABC123\nSeat: 12A\nStatus: https://www.united.com/en/us/flightstatus",
  "isRebooking": false,
  "oldFlightNumber": null,
  "tags": ["multi-segment"]
}
```

### Hotel reservation
```json
{
  "type": "hotel",
  "source": "marriott",
  "confirmationNumber": "XYZ789",
  "summary": "🏨 Grand Plaza Hotel — Chicago",
  "start": "2026-03-20T15:00:00-05:00",
  "end": "2026-03-22T11:00:00-05:00",
  "location": "100 Example Ave, Chicago, IL 60601",
  "description": "Confirmation: XYZ789\nRooms: 1\nGuests: 1",
  "isRebooking": false,
  "oldFlightNumber": null,
  "tags": ["business-travel"]
}
```

### Work assignment (onsite)
```json
{
  "type": "assignment",
  "source": "work-assignment",
  "confirmationNumber": "ASSIGN-2026-04-07-2026-04-11",
  "summary": "🏢 Onsite: New York",
  "start": "2026-04-07T09:00:00-04:00",
  "end": "2026-04-11T17:00:00-04:00",
  "location": "456 Example Blvd, New York, NY 10001",
  "description": "Assignment Code: ON\nProject: TBD",
  "isRebooking": false,
  "oldFlightNumber": null,
  "tags": ["onsite"]
}
```

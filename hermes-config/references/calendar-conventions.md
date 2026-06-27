# Calendar Conventions

> **Durable, user-agnostic reference.** Conventions only — no traveler data. The
> calendar id, home airport, notification channel, locale, and alert lead are
> per-principal memory keys (see `MEMORY.md`), referenced below by name, never by
> value.

Canonical rules for Google Calendar event creation, deduplication, conflict
detection, and notification — applied by `managing-calendar-travel`. The booking
data model is [standard-booking-schema.md](standard-booking-schema.md); the API
mechanics are [gmail-ops.md](gmail-ops.md).

## Event color mapping

Google Calendar's built-in palette. These codes are authoritative across all skills:

| Type | Color | `colorId` |
|------|-------|-----------|
| Flight | Blueberry | `9` |
| Hotel | Sage | `2` |
| Car rental | Tangerine | `6` |
| Assignment | Graphite | `10` |

List the live palette with:

```bash
python3 /data/hermes/skills/productivity/google-workspace/scripts/google_api.py \
  calendar colors --format json
```

## Time format (ISO 8601 + timezone)

Every event time MUST carry an explicit timezone offset or `Z`.

```
2026-03-07T14:30:00-06:00     valid (CST, UTC-6)
2026-03-07T09:15:00Z           valid (UTC)
2026-03-07T14:30:00            INVALID — missing timezone (calendar create fails 400)
2026-03-07 14:30               INVALID — not ISO 8601
```

Extract the timezone from the email when present; otherwise infer it from the event
location's airport/city (see [airports-timezones.md](airports-timezones.md)).

## Deduplication strategy

**Search before create.** Look for an existing event in a ±2-day window around the
booking dates against `travel_calendar_id`:

```bash
python3 /data/hermes/skills/productivity/google-workspace/scripts/google_api.py \
  calendar list \
  --calendar "<travel_calendar_id>" \
  --start "<booking start − 2d, ISO+TZ>" \
  --end   "<booking end + 2d, ISO+TZ>"
```

Match in priority order: (1) RFC 822 `Message-ID` of the source email; (2)
confirmation number in the description; (3) provider + flight/booking number; (4)
summary + start date + location (heuristic). On a match, **update** rather than
create — this preserves any post-booking edits (color, notes).

## Rebooking detection & conflict resolution

A rebooking is the same confirmation code issued for a different flight/date. When a
StandardBooking has `isRebooking: true` and an existing event shares the confirmation
number:

1. Delete the old event.
2. Create the new event with updated times/identifier.
3. Append to the description: `Rebooked from <oldFlightNumber> — <reason if known>`.

**Conflict check:** before committing, scan ±3 hours for overlaps. Same-provider
overlap (e.g. two flights) → report and escalate to the operator. Cross-category
overlap (flight + hotel same day) → allow (expected on travel days).

## Summary field rules

| Type | Format | Notes |
|------|--------|-------|
| Flight | `✈️ UA1875 ORD→LAX` | airline+number + route (codes, `→`); no times |
| Hotel | `🏨 <property> — <city>` | no check-in/out times |
| Car | `🚗 National Car Rental ORD` | company + pickup code; no times |
| Assignment (onsite) | `🏢 Onsite: <city>` | only when the work location ≠ home base |
| Assignment (remote) | `🏢 Remote: <home city>` | work-from-home |

Use `Onsite:` **only** when the employer location is distinct from the principal's
home base; never for same-city assignments or remote work.

## Description field rules

Multi-line text; **raw URLs only — never markdown links** `[text](url)`. Mobile
calendar clients render markdown links poorly or crash on them.

```
Confirmation: ABC123
Seat: 12A
Status: https://www.united.com/en/us/flightstatus
```

Include: confirmation code(s), booking/reference numbers, seat/room/rental detail,
rebooking notes, and raw URLs to booking/status/receipt pages. For multi-segment
itineraries, describe each leg on its own line.

## Email archival

After a successful create/update, archive the source email and apply the processed
label (`travel_bookings_label`):

```bash
python3 /data/hermes/skills/productivity/google-workspace/scripts/google_api.py \
  gmail modify <MESSAGE_ID> --remove-labels UNREAD,INBOX --add-labels "<travel_bookings_label>"
```

## Home-airport arrival alerts

**Trigger:** a flight whose arrival airport equals the `home_airport` memory key.
When `home_airport` is unset, arrival alerts are disabled.

**Lead time:** `alert_lead_hours` before departure (default 48).

**Channel:** the logistics group ONLY — `travel_notify_chat_id` over
`travel_notify_channel`. **Never** the operator DM (`dm_chat_id`): per the channel
boundary, the operator DM carries technical/infra messages, not arrival heartbeats.
Render in the group's `notify_locale` when set.

**Format** (single line, scannable, **raw URL — no markdown**):

```
✈️ UA1875 ORD→<home_airport> | Mar 15, 2:30 PM | Status: On Time
https://www.united.com/en/us/flightstatus
```

## Personal vs. business categorization

Decided at parse time, stored in `tags`:

| Criteria | Category | Note |
|----------|----------|------|
| Matching work assignment over overlapping dates | `business-travel` | `Onsite:` prefix when location ≠ home |
| Arrived via the employer's corporate TMC | `business-travel` | always |
| Consumer OTA / personal card, no assignment | `personal-travel` | no `Onsite:` prefix |
| Uncertain | `personal-travel` | safe default |

## RFC 822 Message-ID dedup key

When a booking originates from a Gmail message, capture its RFC 822 `Message-ID` and
record it for reconciliation so the same email never produces a duplicate event:

```bash
python3 /data/hermes/skills/productivity/google-workspace/scripts/google_api.py \
  gmail search "rfc822msgid:<MESSAGE_ID>" --max 1
```

## Notification cadence (group chat only)

When `travel_notify_chat_id` + `travel_notify_channel` are set:

1. **New home-airport arrivals:** group alert at `alert_lead_hours` before departure.
2. **Rebookings:** update notice within ~1 hour of the calendar update.
3. **Cancellations:** notice immediately.
4. Keep group messages short and single-line; send full diagnostic detail to the operator DM only on explicit request.

## Timezone edge cases

For a flight crossing time zones: parse departure in the **origin** airport's local
zone, then express arrival in the **destination** zone — storing each of `start`/`end`
with its own offset.

```
Departure: 2026-03-15T14:30:00-05:00   (CST, Chicago)
Arrival:   2026-03-15T16:45:00-07:00   (MST, Denver)
```

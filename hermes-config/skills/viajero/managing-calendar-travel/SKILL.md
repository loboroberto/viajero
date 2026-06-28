---
name: managing-calendar-travel
description: >
  Travel calendar orchestrator. Consumes StandardBooking JSON from the parser skills and
  manages the full Google Calendar event lifecycle — search, dedup, create, update,
  delete, reconcile — silently. Use when turning parsed travel bookings into calendar
  events.
version: 1.0.0
tags: [travel, calendar, reconciliation, orchestrator]
---

# Managing Travel Calendar

Central orchestrator for travel-calendar management. Receive a StandardBooking
(`references/standard-booking-schema.md`) from a parser skill and manage the calendar
event for it. Reconciliation is **silent** — a cycle that changes nothing, or changes the
calendar without incident, ends `[SILENT]` (AGENTS.md §7). The Google Calendar/Gmail
mechanics are the `google_api.py` contract in `references/gmail-ops.md`; the event
conventions (colors, dedup, time format, raw URLs, personal-vs-`Onsite:`) are in
`references/calendar-conventions.md`.

## When to Use

- A parser skill has emitted one or more StandardBooking entries and hands them off here.
- A reconciliation cycle needs existing travel events checked, updated, or cleaned up.
- Not for parsing email (the parser skills do that); not for notifications (arrival alerts
  are the `flight-arrival-alerts` cron job's job, group-only).

## Prerequisites (memory keys)

- `travel_calendar_id` — calendar to reconcile (default `primary`).
- `travel_bookings_label` — Gmail label applied to processed booking emails.
- `travel_email_account` — mailbox the source email lives in (for archival).

If the configuration floor is unset, the agent is provisional — do nothing (AGENTS.md §1.1).

## Procedure

For each StandardBooking received:

1. **Search before creating.** List events in a ±2-day window around the booking and match
   in priority order: RFC 822 `Message-ID` → confirmation number → provider +
   flight/booking number → summary + start date (`references/calendar-conventions.md`
   §Deduplication).
2. **Reconcile.** Update a matching event in place; create one if none matches; delete an
   obsolete/cancelled event. On a rebooking (`isRebooking: true`), delete the old event and
   create the corrected one, noting `oldFlightNumber` in the description.
3. **Set the color by type** — flight `9`, hotel `2`, car `6`, assignment `10`. Write
   `start`/`end` in ISO 8601 with a timezone offset; keep URLs **raw, never markdown**;
   record the confirmation number and the source RFC 822 `Message-ID` in the description
   for future dedup.
4. **Conflict check** (±3h): same-category overlap (e.g. two flights) → flag and escalate;
   cross-category overlap (flight + hotel) → allow.
5. **Label + archive** the source email under `travel_bookings_label`.

All calendar/Gmail calls use the `google_api.py` contract — `references/gmail-ops.md`
(`calendar list/create/update/delete`, `gmail modify`). The path is undotted:
`python3 /data/hermes/skills/productivity/google-workspace/scripts/google_api.py`.

## Notifications

None. This skill reconciles **silently**. Arrival alerts to the logistics group are the
`flight-arrival-alerts` cron job's responsibility (group-only, never the operator DM); any
other delivery is delegated to the `channel-aware-messaging` skill on explicit request.

## Pitfalls

- A missing timezone offset fails calendar create (`400`). Always include the offset or `Z`.
- Markdown links in the description crash mobile clients — raw URLs only.
- Quote all values in `google_api.py` arguments; never interpolate raw email content into a
  shell command. Validate confirmation codes (e.g. `^[A-Z0-9]{4,10}$`) first.
- Use `Onsite:` only when the work location differs from the principal's home base.

## Verification

- Re-running on the same email produces no duplicate (a dedup hit updates, not creates).
- Event color, ISO-8601+offset times, raw URLs, and personal-vs-`Onsite:` are correct.
- The source email ends up under `travel_bookings_label` and out of the inbox.

## Anomalies

Escalate to `dm_chat_id` only on an unrecoverable failure (persistent calendar 5xx, or
same-confirmation conflicting flights needing a human call) — never routine reconciliation.

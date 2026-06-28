---
name: parsing-corporate-tmc-booking
description: >
  Parse corporate travel-management (TMC) itinerary emails — flights, hotels, and cars
  bundled in one booking — into StandardBooking JSON. The TMC sender domain is
  principal-specific and read from the active employer definition, never hard-coded. Use
  when processing corporate-TMC booking or update emails.
version: 1.0.0
tags: [travel, parsing, corporate-tmc, multi-segment]
---

# Parsing Corporate-TMC Bookings

Parse a corporate travel-management platform's itinerary email into StandardBooking JSON
(`references/standard-booking-schema.md`) and hand each segment to
`managing-calendar-travel`. A TMC books flights, hotels, and cars on the employer's behalf
under one itinerary — **decompose it into a separate StandardBooking per segment**. See the
Corporate Travel Management (TMC) section of `references/provider-patterns.md` and the Gmail
contract in `references/gmail-ops.md`.

## When to Use

- An unprocessed email arrives from the employer's configured TMC domain.
- The principal travels for business through a corporate booking tool.
- Skip entirely for personal-only travel (no employer definition configured).

## Resolving the TMC sender (no hard-coded domain)

The TMC platform differs per employer, so the sender is **not** hard-coded here:

1. Read the `employer_definition_file` memory key → the employer definition at
   `references/employers/<slug>.md`.
2. Take its `sender_patterns` (`references/employers/schema.md`) and build the Gmail search
   from them (excluding `-label:<travel_bookings_label>`).
3. If `employer_definition_file` is unset or the file is missing, fall back to
   `references/employers/default.md`. If neither resolves a usable sender pattern, **fail
   closed** — skip TMC reconciliation this cycle.

## Procedure

1. **Find** unprocessed TMC mail with the resolved sender patterns (positional Gmail query
   per `references/gmail-ops.md`); read full messages with `gmail get`.
2. **Decompose** the itinerary into one StandardBooking per segment:
   - `source: corporate-tmc`; `type` is `flight` / `hotel` / `car` per segment.
   - summary/emoji, ISO 8601 `start`/`end` **with a timezone offset**, and `location` per
     `references/standard-booking-schema.md` and `references/calendar-conventions.md`.
   - record the source email's RFC 822 `Message-ID` for dedup; share the itinerary's
     confirmation code across its segments.
   - tag `business-travel` (a TMC booking is business by definition —
     `references/provider-patterns.md`).
3. **Updates / cancellations:** most recent email wins; a cancellation deletes the matching
   event (handled by `managing-calendar-travel`).
4. **Hand off** each segment to `managing-calendar-travel`. Reconciliation is `[SILENT]`;
   this skill sends no notifications.

## Pitfalls

- Never hard-code a TMC domain — always resolve it from the employer definition, and fail
  closed when it cannot be resolved.
- Include timezone offsets; quote all `google_api.py` arguments; never interpolate raw
  email HTML into a command.

## Verification

- One StandardBooking per segment; `source: corporate-tmc`; `business-travel` tag.
- No TMC domain literal appears in the skill — the sender comes from the employer definition.

## Anomalies

Escalate to `dm_chat_id` only on a repeated unrecoverable parse/API failure — never routine activity.

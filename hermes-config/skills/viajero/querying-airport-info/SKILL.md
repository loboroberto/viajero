---
name: querying-airport-info
description: >
  Resolve airport codes to names, cities, and IANA timezones for travel parsing and
  alerting. Status: Stub — query types and output shape are defined; the lookup data source
  is not yet wired. Use when an airport code needs to be resolved to a name or timezone.
version: 1.0.0
tags: [travel, airport, timezone, lookup, stub]
---

# Querying Airport Info

> **Status: Stub** — the query types and output shape are specified below; the lookup data
> source is not yet wired (a later issue completes it).

Resolve airport identity and timezone so parser skills can set correct ISO-8601 offsets and
the flight-alert path can match `home_airport`. The timezone conventions and the curated
home-base table are in `references/airports-timezones.md`.

## When to Use

- A parser has an IATA code but needs the airport's full name, city, or IANA timezone for a
  StandardBooking (`references/standard-booking-schema.md`).
- The flight-alert path needs to confirm an arrival airport equals `home_airport`.

## Query types

- **Code → identity:** `ORD` → `Chicago O'Hare International Airport, Chicago, IL, USA`.
- **City → code:** `Chicago` → `ORD`.
- **Code → timezone:** `LHR` → `Europe/London` (drives ISO-8601 offsets, DST-aware).

## Output (shape)

An airport object: IATA code, full name, city, country, IANA timezone (and lat/long when
available).

## Procedure (outline — not yet implemented)

1. Look up the code/city against the airport reference (see
   `references/airports-timezones.md`).
2. Return the resolved object; the IANA timezone is what callers use to build offsets.

## Pitfalls

- Timezone offsets are **DST-aware** — return the IANA zone, not a fixed offset; let the
  caller resolve the offset for the specific date.
- If a code cannot be resolved, fail closed (report unknown) rather than guess a timezone.

## Verification

- When implemented: a known code resolves to the correct IANA timezone; an unknown code
  reports unknown instead of guessing.

## Anomalies

Escalate to `dm_chat_id` only on a repeated unrecoverable failure — never routine activity.

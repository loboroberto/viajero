# Airports & Timezones

> **Durable, user-agnostic reference.** Conventions only. The illustrative airport
> codes below are examples, NOT a principal's home base — the home airport is the
> per-principal `home_airport` memory key.

How to resolve airport codes to timezones so flight legs satisfy the ISO 8601 +
timezone rule in [calendar-conventions.md](calendar-conventions.md), and how the home
airport gates arrival alerts.

## Per-leg local time

Air travel crosses time zones, so a flight's two endpoints carry **different**
offsets. For each leg:

1. Resolve the **origin** airport (IATA) to its IANA timezone; express the departure
   in that local time with its offset.
2. Resolve the **destination** airport to its IANA timezone; express the arrival in
   that local time with its offset.
3. Store each on the StandardBooking (`start` = origin-local departure, `end` =
   destination-local arrival), each with its own offset.

```
Departure: 2026-03-15T14:30:00-05:00   (ORD, America/Chicago, CST)
Arrival:   2026-03-15T16:45:00-07:00   (DEN, America/Denver, MST)
```

## Resolving IATA → IANA timezone

Prefer a **timezone library or live lookup** over a hard-coded master list — there are
thousands of airports and DST rules change. A small set of illustrative mappings (NOT
exhaustive, NOT a home base):

| IATA | IANA timezone |
|------|---------------|
| ORD | America/Chicago |
| JFK | America/New_York |
| DEN | America/Denver |
| LHR | Europe/London |
| NRT | Asia/Tokyo |

For airports not in a lookup, take the timezone from the booking email's stated local
times where present; otherwise derive it from the airport's city/region.

## DST

IANA timezones encode daylight-saving transitions, so the **offset depends on the
date** (e.g. `America/Chicago` is `-06:00` in winter, `-05:00` in summer). Always
compute the offset for the specific travel date — never assume a fixed offset for a
zone. This matters around transition weekends.

## Home airport & arrival alerts

The `home_airport` memory key (an IATA code) gates home-airport arrival alerts: a
flight is alert-eligible only when its **arrival** airport equals `home_airport`.
When `home_airport` is unset, arrival alerts are disabled. Alert timing, channel
(logistics group only), and format are defined in
[calendar-conventions.md](calendar-conventions.md). The principal's home timezone is
the separate `home_timezone` key (IANA, fallback `UTC`).

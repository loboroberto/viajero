---
name: parsing-employer-assignment
description: >
  Parse employer work-assignment emails into StandardBooking JSON and hand them to
  managing-calendar-travel for silent reconciliation. Reads every employer fact — sender
  patterns, assignment codes, offices, business hours, travel detection — from the active
  employer definition, never hard-coded, and emits an onsite or remote business-hours span
  plus travel-day placeholders when travel is detected. Use when processing work-assignment
  notification emails.
version: 1.0.0
tags: [travel, parsing, assignment, employer]
---

# Parsing Employer Assignments

Parse an employer work-assignment email into StandardBooking JSON
(`references/standard-booking-schema.md`) and hand each entry to `managing-calendar-travel`
for silent reconciliation. The engine is **employer-agnostic**: every employer fact — sender
patterns, assignment codes, office locations, business hours, travel-detection method —
comes from the active employer definition (`references/employers/schema.md`), never from this
skill. Reconciliation is `[SILENT]` (AGENTS.md §7); this skill sends no notifications. Gmail
and Calendar mechanics are the `google_api.py` contract in `references/gmail-ops.md`; event
conventions (colors, `Onsite:`/`Remote:` rules, ISO-8601+offset, raw URLs) are in
`references/calendar-conventions.md`.

## When to Use

- An unprocessed work-assignment email arrives from the employer's configured sender (the
  employer definition's `sender_patterns`).
- **Only when an employer is configured** — `employer_definition_file` is set. Skip entirely
  for personal-only travel: the permissive `default.md` fallback must never turn ordinary
  mail into assignment events.
- Not for corporate-TMC itineraries (flights/hotels/cars → `parsing-corporate-tmc-booking`);
  not for calendar writes (→ `managing-calendar-travel`).

## Prerequisites (memory keys)

- `travel_email_account` — mailbox scanned for assignment mail.
- `travel_assignments_label` — Gmail label for processed assignment emails (search exclusion
  and archival target).
- `employer_definition_file` — path to the active employer definition; falls back to
  `references/employers/default.md`.
- `travel_calendar_id` — calendar scanned for travel-flagged events (default `primary`).
- `home_city`, `home_timezone`, `home_airport` — home base for remote spans and travel legs.
- `assignment_type_codes` — *legacy* onsite↔remote code map; used only when the employer
  definition is unavailable.

If the configuration floor is unset, the agent is provisional — do nothing (AGENTS.md §1.1).

## Resolving the employer definition

1. Read `employer_definition_file` → the definition at `references/employers/<slug>.md`; if
   unset or missing, fall back to `references/employers/default.md`
   (`references/employers/schema.md` §Selection).
2. Read its frontmatter: `sender_patterns`, `assignment_types.{onsite,remote}.codes`,
   `office_locations.{default,secondary}`, `business_hours.{start,end,days}`,
   `travel_detection.{method,pattern}`.
3. **Validate the sender** against `sender_patterns`. When the list is non-empty, require a
   match. When empty (the `default.md` case), sender validation is permissive — rely on the
   assignment code and dates instead, and fail closed when no code is present.

`parsing-corporate-tmc-booking` also reads `sender_patterns` (for the TMC platform sender);
the two skills share the list and disambiguate by **content** — this engine requires a
recognizable assignment code, the TMC skill requires a decomposable itinerary. Worked
example: `references/employers/example-corp.md`.

## Procedure

1. **Find** unprocessed assignment mail: build a **positional** Gmail query from
   `sender_patterns`, excluding `-label:<travel_assignments_label>` (`references/gmail-ops.md`
   — the query is positional, there is no `--query` flag). Read full messages with
   `gmail get`; capture each message's RFC 822 `Message-ID` for dedup.
2. **Classify.** Extract the assignment code from the subject/body and match it
   **case-insensitively** against `assignment_types.onsite.codes` /
   `assignment_types.remote.codes` (legacy fallback: the `assignment_type_codes` memory key).
   - **No code found → remote** (safer assumption — no spurious travel;
     `references/employers/default.md`).
   - **Code found but in neither list (unknown) → skip** that email and end `[SILENT]`.
3. **Extract dates** — assignment start (first business day) and end (last business day). If
   either lands outside `business_hours.days`, snap to the nearest in-window business day.
4. **Resolve location.** Onsite: the office named/addressed in the email, else
   `office_locations.default` (or a matching `secondary` office). Remote: `home_city`.
5. **Emit StandardBookings** (`type: assignment`, `source: work-assignment` —
   `references/standard-booking-schema.md`). `confirmationNumber` for the main span =
   `ASSIGN-<start>-<end>` (ISO dates) — the dedup / most-recent-wins key.
   - **Onsite span — a single span over the full duration, never daily events:** `summary`
     `🏢 Onsite: <office city>`; `start` = first business day at `business_hours.start`,
     `end` = last business day at `business_hours.end`, each ISO-8601 **with the office's
     local offset** (infer from the office city per `references/airports-timezones.md`);
     `location` = the full office address; `description` =
     `Assignment Code: <code>\nProject: <name|TBD>`; tags `["onsite", "business-travel"]`
     (`business-travel` so overlapping flights categorize correctly —
     `references/provider-patterns.md`). Use the `🏢 Onsite:` prefix **only when the office
     city ≠ `home_city`** (`references/calendar-conventions.md` §Summary); an in-town onsite
     has no travel and uses the home-base rendering.
   - **Travel placeholders — onsite only, when travel is detected (step 6):** two
     `assignment` legs — `✈️ Out: <home_airport>` the day before the assignment start, and
     `✈️ Home` the day after the assignment end — each ~06:00–20:00 in `home_timezone`; tags
     `["travel-placeholder", "business-travel"]`; deterministic confirmation numbers
     (`ASSIGN-<start>-<end>-OUT` / `-HOME`) so they dedup and so `managing-calendar-travel`
     can replace them when real flights later arrive.
   - **Remote span:** `summary` `🏢 Remote: <home_city>`; `start`/`end` at `business_hours`
     in `home_timezone`; `location` = `home_city`; `description` =
     `Assignment Code: <code>\nProject: <name|TBD>`; tags `["remote"]`.
6. **Travel detection (onsite only)** per `travel_detection.method`:
   - `calendar_scan` — list events on `travel_calendar_id` in a ±2-day window around the
     assignment dates and look for events matching `travel_detection.pattern`
     (`calendar list --calendar --start --end`, `references/gmail-ops.md`). Found → emit
     placeholders; none → onsite span only (travel TBD).
   - `email_flag` — inspect the assignment email's own labels/flags for
     `travel_detection.pattern`. Present → emit placeholders; absent → span only.
7. **Hand off** every StandardBooking to `managing-calendar-travel` (dedup, colorId `10`,
   create/update/clean — `[SILENT]`). Most-recent-email-wins is automatic: re-emitting the
   same `ASSIGN-<start>-<end>` updates the existing event instead of duplicating.
8. **Archive** the source email under `travel_assignments_label`:
   `gmail modify <ID> --remove-labels UNREAD,INBOX --add-labels <travel_assignments_label>`
   (`references/gmail-ops.md`).

## Pitfalls

- **No employer literals.** Every code/domain/office/hour comes from the employer
  definition — never hard-code one. Fictional literals live only in
  `references/employers/example-corp.md`.
- **Fail closed.** Empty `sender_patterns` + no extractable code → emit nothing; unknown
  code → skip + `[SILENT]`. Never guess an assignment type from an ambiguous email.
- **Onsite ≠ travel.** Emit placeholders only when `travel_detection` actually fires; an
  in-town onsite (office city = `home_city`) gets neither the `Onsite:` prefix nor placeholders.
- **Timezones.** Onsite spans use the **office's** local offset; remote spans and placeholders
  use `home_timezone`. A missing offset fails calendar create (`400`).
- **Security.** Quote every `google_api.py` argument; never interpolate raw email subject/body
  into a shell command. Use `python3` and the undotted path
  `/data/hermes/skills/productivity/google-workspace/scripts/google_api.py`.

## Verification

- One main StandardBooking per assignment (`type: assignment`, `source: work-assignment`);
  onsite = a single full-duration span, not daily events; placeholders only when travel was detected.
- No employer literal appears in the skill — codes/offices/hours all resolve from the definition.
- Re-running on the same email updates in place (shared `ASSIGN-<start>-<end>`) with no
  duplicate; the email ends under `travel_assignments_label` and out of the inbox.

## Anomalies

Escalate to `dm_chat_id` only on an unrecoverable infra/parse failure (employer definition
unreadable, Gmail/Calendar persistently down) — never routine reconciliation.

---
# Generic fallback employer definition. Used when `employer_definition_file` is
# unset or points at a missing file. Permissive and conservative. Field reference:
# references/employers/schema.md.
name: "Generic Employer"
domains: []
sender_patterns: []
assignment_types:
  onsite:
    codes: ["ON", "ONSITE", "SITE"]
  remote:
    codes: ["WFH", "REMOTE", "REM"]
office_locations:
  default: "Unknown"
business_hours:
  start: 9
  end: 17
  days: [1, 2, 3, 4, 5]
travel_detection:
  method: "calendar_scan"
  pattern: "travel-flagged"
---

# Generic Employer Assignment Parsing

Fallback rules when no employer-specific definition is available. A principal who
registers their employer (copy [template.md](template.md), set
`employer_definition_file`) overrides everything here.

## Assignment Type Detection

The assignment code is matched **case-insensitively** against the codes above.

- **Onsite:** `ON`, `ONSITE`, `SITE`
- **Remote:** `WFH`, `REMOTE`, `REM`

If no code is found, default to **remote** (the safer assumption — no spurious travel).

## Time Rules

- **Business hours:** 09:00–17:00.
- **Business days:** Mon–Fri.
- **Timezone:** the `home_timezone` memory key, or `UTC` if unset.

## Travel Detection

For an onsite assignment, scan the calendar in a ±2-day window around the assignment
dates for `travel-flagged` events. With no employer `domains`/`sender_patterns`
configured, sender validation is permissive — rely on the assignment code and dates.

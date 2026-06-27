---
# FICTIONAL worked example — a learning reference, NOT a real employer. "Example
# Corp" / example.com are reserved illustrative names. Field reference:
# references/employers/schema.md.
name: "Example Corp"
domains: ["example.com"]
sender_patterns:
  - "assignments@example.com"
  - "*@example.com"
assignment_types:
  onsite:
    codes: ["ON", "SITE"]
  remote:
    codes: ["WFH", "REMOTE"]
office_locations:
  default: "100 Example Ave, Springfield, IL 62701"
  secondary:
    - name: "West Office"
      address: "200 Sample St, Portland, OR 97201"
    - name: "East Office"
      address: "456 Example Blvd, New York, NY 10001"
business_hours:
  start: 9
  end: 17
  days: [1, 2, 3, 4, 5]
travel_detection:
  method: "calendar_scan"
  pattern: "travel-flagged"
---

# Example Corp Assignment Parsing

This is a fully-worked **fictional** employer definition demonstrating the schema
end-to-end. Copy [template.md](template.md) (not this file) when registering a real
employer.

## Email Structure

Subject: `[<PROJECT-NAME>] Assignment: <CODE> | <start> - <end>`

Body fields:
- Assignment code (see Code Meanings)
- Project / engagement name
- Start date (first business day) and end date (last business day)
- Office location (if omitted, use `office_locations.default`)

## Code Meanings

- **ON, SITE** — onsite at the assigned office; travel expected.
- **WFH, REMOTE** — work-from-home; no travel.

## Travel Detection

For an onsite code, scan the calendar for `travel-flagged` events within ±2 days of
the assignment dates. If found, the assignment includes travel legs; if not, treat
travel as TBD.

## Example Email

```
From: assignments@example.com
Subject: [Q2 West Coast] Assignment: ON | 2026-04-07 - 2026-04-11

Your assignment is confirmed:

Project: Q2 West Coast Client Engagement
Assignment Code: ON
Dates: April 7-11, 2026 (Mon-Fri)
Location: West Office, 200 Sample St
```

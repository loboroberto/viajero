---
# Employer definition template — copy to references/employers/<slug>.md and fill in.
# Field reference: references/employers/schema.md. Read by the employer-assignment
# engine, selected via the `employer_definition_file` memory key. No principal
# personal data (home address, account ids, secrets) belongs in this file.
name: ""
domains: []
sender_patterns: []
assignment_types:
  onsite:
    codes: []
  remote:
    codes: []
office_locations:
  default: ""
  secondary: []
    # - name: ""
    #   address: ""
business_hours:
  start: 9
  end: 17
  days: [1, 2, 3, 4, 5]   # 0=Sun … 6=Sat
travel_detection:
  method: "calendar_scan"  # calendar_scan | email_flag
  pattern: "travel-flagged"
---

# <Employer Name> Assignment Parsing

_Fill in the sections below. This narrative gives the engine context on how this
employer's assignment emails are shaped. Delete these italic notes when done._

## Email Structure

_How assignment emails are formatted (subject pattern, body fields)._

## Code Meanings

_What each onsite/remote code in the frontmatter signifies._

## Travel Detection

_How to tell whether an onsite assignment includes travel (the `travel_detection`
method/pattern above)._

## Example Email

```
_(paste one representative, sanitized assignment email)_
```

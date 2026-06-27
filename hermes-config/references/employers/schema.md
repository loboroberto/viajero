# Employer Definition Schema

> **Durable, user-agnostic reference.** This defines the *format* of an employer
> definition — the declarative data the employer-assignment engine reads. It
> contains no real employer, no codes, no addresses. A principal's actual employer
> definition is a separate file in this directory (created at onboarding); see
> [template.md](template.md) to start one, [example-corp.md](example-corp.md) for a
> fully-worked fictional example, and [default.md](default.md) for the generic
> fallback.

## What this is (and is not)

An **employer definition** is a `references/employers/<slug>.md` file with YAML
frontmatter (machine-readable config) plus a markdown narrative (human notes on the
employer's email format). The **employer-assignment engine skill** reads it to turn a
work-assignment email into a [StandardBooking](../standard-booking-schema.md).

> **Boundary:** this file (and the engine) belong to different issues. The *definition
> format and data* are reference content. The *engine logic* — how an email is parsed,
> codes extracted, travel legs detected, and StandardBookings emitted — lives in the
> employer-assignment **skill**, not here. This document deliberately specifies only
> the data contract the engine consumes; it contains no parsing algorithm.

## Selection

The engine loads the file named by the `employer_definition_file` memory key (a path
relative to the agent home, e.g. `references/employers/<slug>.md`). If that key is
unset or the file is missing, it falls back to `references/employers/default.md`.

## YAML frontmatter fields

| Field | Type | Required | Meaning |
|-------|------|----------|---------|
| `name` | string | yes | human-readable employer name |
| `domains` | list&lt;string&gt; | yes | email domains owned by the employer |
| `sender_patterns` | list&lt;string&gt; | yes | glob/email patterns that identify an assignment sender (e.g. `*@example.com`, `assignments@example.com`) |
| `assignment_types.onsite.codes` | list&lt;string&gt; | yes | codes that mean *onsite* (travel expected) |
| `assignment_types.remote.codes` | list&lt;string&gt; | yes | codes that mean *remote* (work-from-home) |
| `office_locations.default` | string | yes | default onsite address/name when the email omits one |
| `office_locations.secondary` | list&lt;{name,address}&gt; | no | additional named offices |
| `business_hours.start` | int (0–23) | yes | first business hour (e.g. `9`) |
| `business_hours.end` | int (0–23) | yes | last business hour (e.g. `17`) |
| `business_hours.days` | list&lt;int&gt; | yes | business days, `0`=Sun … `6`=Sat (e.g. `[1,2,3,4,5]`) |
| `travel_detection.method` | string | yes | `calendar_scan` or `email_flag` |
| `travel_detection.pattern` | string | yes | the label/tag the method looks for (e.g. `travel-flagged`) |

## Narrative body convention

Below the frontmatter, document — for a human and for the engine's prompt context —
the employer's assignment-email shape. Recommended sections:

- **Email Structure** — subject/body format the assignments arrive in.
- **Code Meanings** — what each onsite/remote code signifies.
- **Travel Detection** — how to tell whether an onsite assignment includes travel.
- **Example Email** — one representative (sanitized) assignment email.

## Conventions

- **Codes are matched case-insensitively** by the engine.
- **`office_locations` and addresses are durable** employer facts, fine to commit —
  but never put a principal's personal data (home address, account ids, secrets) in
  an employer file.
- Adding a new employer is one file: copy [template.md](template.md), fill the
  frontmatter, write the narrative, and point `employer_definition_file` at it.

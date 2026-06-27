# Gmail & Calendar Operations

> **Durable, user-agnostic reference.** The API contract only — no traveler data.
> The account, calendar id, and label names are per-principal memory keys, named
> below, never valued. OAuth tokens live in `secrets/` on the volume, never here.

Canonical contract for Google Workspace operations via the built-in
`google-workspace` skill's `google_api.py` (the proven Python backend). Used by all
travel skills for Gmail search/label/archive and calendar create/reconcile. Provider
recognition is in [provider-patterns.md](provider-patterns.md); calendar rules in
[calendar-conventions.md](calendar-conventions.md).

## Backend & path

**Script:** `/data/hermes/skills/productivity/google-workspace/scripts/google_api.py`
(`HERMES_HOME=/data/hermes`; the `google-workspace` skill is a bundled keep-skill
synced onto the volume, and the google python libs are installed in the image).

```bash
python3 /data/hermes/skills/productivity/google-workspace/scripts/google_api.py \
  <service> <command> [args]
```

`<service>` ∈ `gmail`, `calendar`, `drive`, `sheets`, `docs`, `contacts`.

> **Email-only deployments (no GCP):** a principal who needs only Gmail
> scan/label/archive/forward (no Calendar) can use the `himalaya` keep-skill with a
> Gmail App Password instead of a GCP OAuth client. Calendar reconciliation requires
> `google_api.py` + a GCP OAuth client. The backend choice is the
> `travel_email_backend` memory key (`himalaya` | `google_api`); onboarding records
> it. This doc describes the `google_api` backend.

## Gmail operations

### Search
```bash
python3 .../google_api.py gmail search "<QUERY>" [--max N] [--account <travel_email_account>]
```
The query is **positional** (there is no `--query` flag). Syntax: standard Gmail
operators (see provider-patterns.md). Output: JSON array of message objects
(`id`, `threadId`, `from`, `to`, `subject`, `date`, `snippet`, `labels`).

```bash
python3 .../google_api.py gmail search "from:(*@united.com) -label:<travel_bookings_label> is:unread" --max 5
```

### Get (full message)
```bash
python3 .../google_api.py gmail get <MESSAGE_ID> [--account <travel_email_account>]
```
Output: full message object incl. `body` / `html` / `labels`.

### Modify (label / archive)
```bash
python3 .../google_api.py gmail modify <MESSAGE_ID> \
  [--add-labels LABEL[,LABEL...]] [--remove-labels LABEL[,LABEL...]]
```
Archive = remove `UNREAD,INBOX`:
```bash
python3 .../google_api.py gmail modify <MESSAGE_ID> --remove-labels UNREAD,INBOX
```

### Labels (list)
```bash
python3 .../google_api.py gmail labels [--account <travel_email_account>]
```
Resolve a label *name* to its id before using `--add-labels` / `--remove-labels`.

### Send
```bash
python3 .../google_api.py gmail send --to RECIPIENT --subject "Subject" --body "Body text"
```
Used by expense forwarding (see [expense-forwarding.md](expense-forwarding.md)).

## Calendar operations

### List
```bash
python3 .../google_api.py calendar list \
  [--calendar <travel_calendar_id>] [--start ISO_START] [--end ISO_END]
```
Defaults: calendar `primary`, start = now, end = now + 7 days. Output: JSON array of
events (`id`, `summary`, `start`, `end`, `location`, `description`, `colorId`, `htmlLink`).

### Create
```bash
python3 .../google_api.py calendar create \
  [--calendar <travel_calendar_id>] \
  --summary "Event Title" --start "ISO_START" --end "ISO_END" \
  [--location "Venue"] [--description "Details"] [--color COLOR_CODE]
```
Times **must** include a timezone offset or `Z`; descriptions use raw URLs (no
markdown); escape quotes for the shell. Output: `{status, id, summary, htmlLink}`.

### Update
```bash
python3 .../google_api.py calendar update <CALENDAR_ID> <EVENT_ID> \
  [--summary ...] [--start ...] [--end ...] [--location ...] [--description ...] [--color ...]
```

### Delete
```bash
python3 .../google_api.py calendar delete <CALENDAR_ID> <EVENT_ID>
```

## Common pitfalls

1. **Missing timezone** → `400 Bad Request: Invalid value for: time`. Always include an
   offset or `Z`: `--start "2026-03-15T14:30:00-06:00"` (not `...T14:30:00`).
2. **`--query` flag for gmail search** → `unrecognized arguments: --query`. The query
   is positional: `gmail search "from:(*@united.com)"`.
3. **Markdown links in descriptions** → mobile clients crash. Raw URLs only:
   `Status: https://…` (not `[Click here](https://…)`).
4. **Shell escaping** in multi-line descriptions — use single quotes, escape internal
   quotes, or pass JSON-escaped values.
5. **`terminal` not defined** in `execute_code` blocks (`NameError: name 'terminal' is
   not defined`) → import it explicitly at the top of the block:
   ```python
   from hermes_tools import terminal
   # then: terminal.run(...)
   ```

## Memory keys for Google setup

Set these before the travel skills run (all are part of the configuration-floor
contract in `MEMORY.md`; onboarding collects them). Values shown are *placeholders*.

| Key | Example placeholder | Description |
|-----|---------------------|-------------|
| `travel_email_account` | `you@example.com` | Gmail account scanned for bookings/receipts |
| `travel_calendar_id` | `primary` | calendar reconciled to |
| `travel_bookings_label` | `Provider Bookings` | label applied to processed booking emails |
| `travel_assignments_label` | `Travel Assignments` | optional — label applied to processed work-assignment emails |
| `travel_email_backend` | `google_api` | `himalaya` (App Password, no GCP) or `google_api` (GCP OAuth) |
| `travel_notify_chat_id` | *(unset)* | logistics-group chat id for notifications |
| `travel_notify_channel` | `telegram` | `telegram` \| `slack` \| `discord` |
| `home_airport` | `<IATA>` | home airport (gates arrival alerts) |
| `home_city` | `<city>` | home city name |
| `home_timezone` | `<IANA TZ>` | e.g. `America/Chicago` (see airports-timezones.md) |
| `assignment_type_codes` | *(unset)* | optional/legacy onsite↔remote code map; canonically the employer definition's `assignment_types` (see [employers/schema.md](employers/schema.md)) |

Loyalty numbers are **secrets**, not memory keys — they live in
`secrets/loyalty_accounts.json` (see [loyalty-registry.md](loyalty-registry.md)).
Employer assignment codes live canonically in the employer definition
(`references/employers/<name>.md` `assignment_types`), pointed to by the
`employer_definition_file` key.

This table covers the keys used for Gmail/Calendar setup. The remaining
configuration-floor keys are documented where they apply — delivery/notification
(`dm_chat_id`, `alert_lead_hours`, `notify_locale`) in
[calendar-conventions.md](calendar-conventions.md), and `expense_receipt_inbox` in
[expense-forwarding.md](expense-forwarding.md). The full contract is consolidated in
`MEMORY.md` (the onboarding skill collects it).

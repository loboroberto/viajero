# USER.md — Principal Model

> **Principal profile not set** — run the `onboarding` skill to capture name(s),
> travel companions, home base, travel patterns, and preferences. AGENTS.md §1.1 gate.

The principal-specific user model (CoALA §4.1, §4.5): who the traveler is and how
they prefer to travel and be notified. Distinct from `MEMORY.md` — claims here are
*about the principal*. Populated per-deployment by `onboarding` and refined over time
by the `coala-reflection` skill; a fresh volume carries no prior traveler's data.

## Identity & companions
- **Name / role:** _(captured during onboarding)_
- **Regular travel companions:** _(partner, family, colleagues — if any)_

## Home base
- **City:** _(see `MEMORY.md` `home_city`)_
- **Timezone:** _(see `MEMORY.md` `home_timezone`)_

## Travel patterns
- **Type:** _(business / personal / mixed)_
- **Cadence & destinations:** _(e.g. monthly; typical routes)_

## Preferences
- **Alert sensitivity:** _(home-airport arrivals only, or all flights)_
- **Preferred providers:** _(carriers / hotel chains / car vendors)_
- **Communication style:** _(formal / casual; locale — see `MEMORY.md` `notify_locale`)_
- **Accessibility / constraints:** _(if any)_

_(empty — onboarding and agent learning populate this)_

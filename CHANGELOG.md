# Changelog

All notable changes to `lian-qa-plugin`. Each entry records the **trigger**
(what real-world problem caused the bump), the **change**, and the **impact**
for QA engineers using the plugin.

Format: [Keep a Changelog](https://keepachangelog.com/en/1.1.0/) · Semver.
Releases before 0.7.0 predate this file and are not recorded here.

---

## [0.7.0] — 2026-08-03

### Changed — `/do-cucumber-task`: synchronization waits are now cross-platform

**Trigger.** The "Synchronization waits (anti-flakiness)" guidance was written
for mobile only, and framed a fixed-duration pause as a last resort gated
behind "the project already has a real wait step, otherwise this whole
subsection is a no-op". On frontend and backend features the section simply
didn't apply, and the last-resort framing pushed toward removing legitimate
pauses that had no better alternative.

**Change.** The subsection now applies to **all platforms** (frontend, mobile,
backend) and states one core principle: prefer waiting on an observable
readiness condition **when one is available**, with a fixed-duration wait as a
valid, allowed fallback. Specifically:

- Per-platform examples of what "observable condition" means — Playwright's
  built-in auto-waiting / a visibility assertion or `waitFor`; an Appium /
  WebdriverIO "wait for element to be displayed" step backed by the project's
  real `waitForDisplayed`; a backend retry-until-condition poll (the MailHog
  retrieval is now called out as an example of that shape).
- A fixed pause (`pause`/`sleep`/`waitForTimeout`) is explicitly **correct**
  when there is genuinely no observable condition or no real wait primitive to
  reuse or wrap — kept as short as is reliable. Added the guardrail: never
  remove an existing pause just to avoid pauses.
- "Never invent a wait step" is **refined, not repealed**: reuse an existing
  readiness-wait step/helper; if none exists but a real primitive does, you may
  add at most ONE thin cross-platform binding that delegates to it. Wrapping a
  real primitive is not inventing; fabricating a wait with no backing primitive
  still is — fall back to a fixed pause instead.
- New rules: never key a wait on a platform-specific signal for cross-platform
  content (e.g. an Android-only `clickable` attribute); prefer a specific
  readiness condition over a coarse one (a preference, not a requirement); and
  don't emit a redundant blind pause before a step that already auto-waits.
- The three pre-existing rules (`@app_reset` cold-start, one-directional
  internal consistency, wait before a negative assertion after a dismissing
  action) are kept, renumbered, and reworded platform-neutrally
  ("state"/"action" instead of "screen"/"tap").
- The Rules bullet about synchronization-wait steps was updated to match.

Reporting is unchanged: every readiness-wait step **or fixed pause** added or
used this way is still listed under "Steps auto-supplemented" in the Report.
All examples are generic — no project's locators, selectors, or timeouts are
hardcoded into the command.

**Impact.** Frontend and backend features now get the same anti-flakiness
treatment mobile already had. Existing pauses in generated or hand-written
features are left alone unless a real observable wait is actually available.
No other command behavior changed.

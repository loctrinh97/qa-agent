---
name: do-cucumber-task
description: Fetch one CucumberStudio scenario, ground it against this workspace's spec.md/scanned-source knowledge, verify its wording against real selectors when available, write/update specs/NNN-<module>/spec.md, and generate features/<module>.feature. Sub-project 1 of 5 — does not generate page objects, step definitions, or run the test yet.
argument-hint: "<cucumberstudio-url>"
---

EXECUTE IMMEDIATELY.

This converts one CucumberStudio scenario into a grounded spec.md + .feature
file. It does NOT generate page objects, step definitions, or run any
test — those are future phases of this plugin.

## Parse the CucumberStudio URL

Expected pattern: `https://studio.cucumberstudio.com/projects/<projectId>/test-plan/folders/<folderId>/scenarios/<scenarioId>`

```bash
URL="$ARGUMENTS"
PROJECT_ID=$(echo "$URL" | grep -oE 'projects/[0-9]+' | grep -oE '[0-9]+')
FOLDER_ID=$(echo "$URL" | grep -oE 'folders/[0-9]+' | grep -oE '[0-9]+')
SCENARIO_ID=$(echo "$URL" | grep -oE 'scenarios/[0-9]+' | grep -oE '[0-9]+')
echo "PROJECT_ID=$PROJECT_ID FOLDER_ID=$FOLDER_ID SCENARIO_ID=$SCENARIO_ID"
```

If any of the three IDs is empty, stop with:
`This doesn't look like a CucumberStudio scenario URL. Expected: https://studio.cucumberstudio.com/projects/<id>/test-plan/folders/<id>/scenarios/<id>`

## Resolve the CucumberStudio MCP tool

```
ToolSearch(query: "cucumberstudio", max_results: 10)
```

- No tools found at all → tell the user:
  ```
  No cucumberstudio MCP server found. Run /add-mcp cucumberstudio first, then retry.
  ```
  Stop.
- Tools found → identify the fetch/get-scenario tool from the result (never
  hardcode a specific tool name — the exact name depends on what's
  installed).

## Fetch the scenario

Call the resolved tool with `PROJECT_ID`, `FOLDER_ID`, `SCENARIO_ID` (exact
parameter names depend on the discovered tool's schema — read it from the
ToolSearch result, don't guess a shape). Expect back: scenario title,
folder/feature title, and the ordered list of steps (Given/When/Then-shaped
text).

- Fetch fails (auth error, not found, network error) → surface the real
  error. Ask: "Fix access and reply 'retry', or paste the scenario's
  Given/When/Then steps here directly?" Wait for the reply.
- Scenario has no steps / empty content → report this, ask the user to
  confirm the URL is correct. Wait for the reply. If they confirm a
  different/corrected URL, restart from "Parse the CucumberStudio URL" with
  it. If they confirm the original URL is right, stop — there's nothing to
  generate from an empty scenario.

## Determine the module name

Derive a candidate module name from the scenario's title or its parent
folder/feature title (sanitize to `[a-z0-9-]`, lowercase, spaces → `-`).

```
Scenario fetched: "<scenario title>" (folder: "<folder title>")
Suggested module name: <candidate>

Reply with a name, or `ok` to use the suggestion.
```
Wait for the reply. If the reply is `ok`, use the candidate as-is. Otherwise,
sanitize whatever the user replied with the same way as the candidate
(`[a-z0-9-]`, lowercase, spaces → `-`). Set `MODULE` to the result.

## Determine the platform

```bash
ls .claude/docs/ 2>/dev/null
```

- Exactly one of `backend`/`frontend`/`mobile` present → use it as
  `PLATFORM`, no need to ask.
- More than one present → ask:
  ```
  Multiple scanned sources found: <list>. Which one is this scenario for?
  Reply: backend / frontend / mobile
  ```
  Wait for the reply.
- None present → ask directly:
  ```
  No scanned source found yet (.claude/docs/ is empty or missing).
  What platform is this scenario for?
  Reply: backend / frontend / mobile
  ```
  Wait for the reply — never guess.

Set `PLATFORM` from whichever branch applied.

## Resolve the grounding/selector source

Branch on `PLATFORM`:

**`backend`** — no selector step. Use `specs/*/spec.md` and/or
`.claude/docs/backend/` content directly for business-logic grounding in
the spec.md write below. Set `SELECTOR_SOURCE=not-applicable`. Skip
straight to "Write/update spec.md".

**`mobile`**:
```bash
ls .claude/docs/mobile/screens.md 2>/dev/null
```
- Exists → ask: "Use the scanned .claude/docs/mobile/screens.md, or connect
  a live app via Appium instead? Reply: scanned / live". Wait for the
  reply.
- Doesn't exist → ask: "No scanned mobile docs found. Can you connect a
  live app via Appium for selector verification? Reply: yes / no". Wait
  for the reply. `yes` → proceed with a live Appium connection (see
  below). `no` → set `SELECTOR_SOURCE=none`, proceed unverified.

If `live` (or `yes` above) was chosen: use Appium MCP to connect to the app
and inspect the relevant screen(s) mentioned in the scenario steps. If the
Appium MCP isn't available (`ToolSearch(query: "appium")` returns nothing),
tell the user to run `/add-mcp appium` first, then retry, or reply `no` to
proceed unverified instead.

**`frontend`**:
```bash
ls .claude/docs/frontend/components.md 2>/dev/null
```
- Exists → ask: "Use the scanned .claude/docs/frontend/components.md, or a
  live website URL instead? Reply: scanned / live". Wait for the reply. If
  `live` → follow up: "What's the live URL to check?" Wait for the reply,
  then proceed with a live Playwright navigation to it.
- Doesn't exist → ask directly: "No scanned frontend docs found. Do you
  have a live website URL I can use to verify selectors? Reply with the
  URL, or `no`." Wait for the reply. A URL given → proceed with a live
  Playwright navigation to it. `no` → set `SELECTOR_SOURCE=none`, proceed
  unverified.

If `live` (or a URL) was chosen: use Playwright MCP to navigate to the
given/known URL and inspect the relevant page(s) mentioned in the scenario
steps. If the Playwright MCP isn't available (`ToolSearch(query:
"playwright")` returns nothing), tell the user to run `/add-mcp playwright`
first, then retry, or reply `no` to proceed unverified instead.

## Verify step wording (only when a selector source was resolved)

For each scenario step that quotes UI text (a button label, heading, or
message), compare it against the resolved source (scanned docs' recorded
text, or the live snapshot/DOM). If the real wording differs from
CucumberStudio's, use the REAL wording in the generated feature and note
the discrepancy for the final report. If `SELECTOR_SOURCE=none`, skip this
verification entirely — every step's wording is used as-is from
CucumberStudio, and the generated feature will carry the "unverified"
marker.

## Write/update spec.md

Determine `<NNN>`:
```bash
ls specs/*-<MODULE>/ 2>/dev/null
```
- Found → read the existing spec; this write updates it in place (adds/
  refreshes the CucumberStudio-derived content, appends a Prompt History
  entry — never delete existing entries).
- Not found → determine the next number:
  ```bash
  LAST=$(ls specs/ 2>/dev/null | sort | tail -1 | grep -oE '^[0-9]+')
  NNN=$(printf '%03d' $(( ${LAST:-0} + 1 )))
  ```

Write (or update) `specs/<NNN>-<MODULE>/spec.md` with this structure:

```markdown
# Spec: <MODULE>

**Status**: Draft
**Source**: CucumberStudio — [<scenario title>](<cucumberstudio-url>)
**Source Last Synced**: <ISO timestamp>
**Platform**: <PLATFORM>
**Target**: <live URL if resolved, else "not yet provided">

## Description

<one-paragraph summary derived from the scenario's steps>

## User Stories

### US1: <scenario title>

- **AC1**: Given <...>, When <...>, Then <...>
  (one AC per Given/When/Then group in the fetched scenario, using
  VERIFIED wording from "Verify step wording" above when available)

## Assumptions / Out of scope

- <anything the scenario's steps didn't cover>

## Prompt History

- <ISO timestamp> — Generated from CucumberStudio scenario via /do-cucumber-task
```

## Validate the spec (5-dimension rubric)

Score against these 5 dimensions (pass=1/fail=0 each):

| Dimension | Passes when |
|---|---|
| Completeness | Every step group in the fetched scenario has a matching AC |
| Clarity | Each AC is unambiguous |
| Testability | Each AC has a concrete, observable Given/When/Then |
| Independence | ACs don't depend on execution order or hidden shared state |
| Traceability | The underlying requirement or scenario traces to something the CucumberStudio scenario actually said — concrete copy/labels/values invented to make an AC testable are fine, but a fabricated requirement or scenario with no basis in the source is not |

5/5 → proceed. <5/5 → fix inline now (this command's input is already a
structured scenario, not free text — do not loop back to a brainstorm
step), re-score once, then proceed regardless.

## Generate the feature file

Write `features/<MODULE>.feature`:

```gherkin
# Generated: <date> | Source: CucumberStudio — <cucumberstudio-url>
# spec: specs/<NNN>-<MODULE>/spec.md
<UNVERIFIED-MARKER-LINE-IF-APPLICABLE>

Feature: <scenario/folder title>

  # AC1: <...>
  Scenario: <scenario title>
    Given <...>
    When <...>
    Then <...>
```

If `SELECTOR_SOURCE=none` (from "Resolve the grounding/selector source"),
the first line after the spec comment must be exactly:
```
# unverified — no selector source available
```
This marker applies only to `SELECTOR_SOURCE=none` — the frontend/mobile
case where a selector source was wanted but unavailable. It must NOT be
added when `SELECTOR_SOURCE=not-applicable` (the backend case, which has
no selector/UI concept and never attempts verification in the first
place).

Never write raw selectors (CSS/XPath/testid strings) into any step —
quoted text is UI copy only, verified or explicitly marked unverified.

## Determine the class name

```bash
CLASS=$(echo "$MODULE" | awk -F'-' '{for(i=1;i<=NF;i++){$i=toupper(substr($i,1,1)) substr($i,2)}}1' OFS='')
echo "CLASS=$CLASS"
```
(e.g. `user-login` → `UserLogin`)

## Re-read the grounding source (no re-fetch, no new live session)

Reuse exactly what "Resolve the grounding/selector source" and "Verify step
wording" already resolved above in this same run — never re-open a
browser/Appium session, never re-ask the user, never re-fetch scanned docs
from scratch.

- `frontend`/`mobile`, `SELECTOR_SOURCE=scanned` → the already-read content
  of `.claude/docs/frontend/components.md` or `.claude/docs/mobile/screens.md`.
- `frontend`/`mobile`, `SELECTOR_SOURCE=live` → the live Playwright/Appium
  snapshot already captured during "Verify step wording" — reuse it. If
  that session is no longer available (e.g. it timed out before this
  point), do not reopen it — treat every element that needed it as
  unverified for the sections below.
- `backend` → `.claude/docs/backend/api-contracts.md` if present, else
  `specs/<NNN>-<MODULE>/spec.md`'s Description/ACs.
- `SELECTOR_SOURCE=none` (or no source available for backend either) →
  every element/endpoint in this module is unverified.

## Scan existing project style

```bash
case "$PLATFORM" in
  frontend) ls pages/*.ts locators/*.ts 2>/dev/null ;;
  mobile)   ls pages/mobile/*.ts locators/mobile/*.ts 2>/dev/null ;;
  backend)  ls api-clients/*.ts 2>/dev/null ;;
esac
```

If a file already exists for this exact module (`pages/<CLASS>Page.ts`,
`pages/mobile/<CLASS>Screen.ts`, or `api-clients/<CLASS>Client.ts`), read
it now — the generation below merges into it (adds new methods/entries for
anything new, leaves existing ones untouched) rather than overwriting it.
If empty/missing, use the default conventions below with no prior style to
match.

## Generate the locator/endpoint file

Skip this section entirely for `backend` — HTTP method/path stay inline in
the API client (see "Generate the page object / screen object / API
client" below); there is no separate locator file for backend.

**`frontend`** — write (or merge new entries into) `locators/<MODULE>.locators.ts`:

```typescript
import { Page } from '@playwright/test';

export const get<CLASS>Locators = (page: Page) => ({
  <elementName>: page.<real-locator-call>,
  // ^ grounded — built from the resolved scanned-docs entry or live snapshot
  <otherElementName>: undefined as any, // TODO: unverified — <element description>
});
```

Selector priority order (already established for this plugin): `getByRole`
→ `getByLabel` → `getByTestId` → `getByText` → CSS (last resort). One entry
per UI element referenced by a step in `features/<MODULE>.feature`.
Grounded elements get a real locator call; ungrounded elements get a
`// TODO: unverified — <description>` comment instead — never invent a
plausible-looking selector.

**`mobile`** — write (or merge new entries into) `locators/mobile/<MODULE>.locators.ts`:

```typescript
export const get<CLASS>Locators = () => ({
  <elementName>: '~<real-accessibility-id>',
  // ^ grounded — Android/iOS accessibility id from scanned docs or live inspection
  <otherElementName>: '', // TODO: unverified — <element description>
});
```

Android/iOS priority order (already established for this plugin):
`accessibility id` → `UiSelector.text()`/`NSPredicate` → `resourceId`/class
chain → `description()` → XPath (last resort).

If a locators file already exists for this module, add new entries for any
new element referenced by the feature file; leave existing entries
untouched.

## Report

```
Spec: specs/<NNN>-<MODULE>/spec.md
Feature: features/<MODULE>.feature
Platform: <PLATFORM>
Selector source: <scanned docs | live Playwright | live Appium | unverified | not applicable (backend)>
Wording discrepancies fixed: <list, or "none">

Not generated yet (future phases): page objects/locators, step definitions,
test execution.
```

## Rules

- Do NOT generate page objects, locators, or step definitions — those are
  future phases of this plugin.
- Do NOT run any test.
- Do NOT run `git` commands — this command only reads/writes files and
  calls MCP tools.
- Never guess a module name, platform, or selector wording — ask when
  ambiguous, mark "unverified" when no source is available.
- Never invent scenario steps not present in the fetched CucumberStudio
  content.

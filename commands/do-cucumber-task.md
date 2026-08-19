---
name: do-cucumber-task
description: Fetch one CucumberStudio scenario, ground it against this workspace's spec.md/scanned-source knowledge, verify its wording against real selectors when available, write/update specs/NNN-<module>/spec.md, generate `<module>.feature` at the project's real feature-file location, generate the grounded page object/screen object/API client (plus locators, for frontend/mobile), generate step definitions, and — by default — smoke-test and auto-un-disable the feature. Pass --no-run to skip the smoke test (e.g. no live device/browser/server available).
argument-hint: "<cucumberstudio-url> [--no-run]"
---

EXECUTE IMMEDIATELY.

This converts one CucumberStudio scenario into a grounded spec.md +
.feature file, the page object/screen object/API client (and locators,
for frontend/mobile), and step definitions underneath it. By default, it
also smoke-tests the freshly-generated feature and removes the @disable
tag when it's genuinely ready — pass --no-run to skip the smoke test.

## Parse the CucumberStudio URL

Expected pattern: `https://studio.cucumberstudio.com/projects/<projectId>/test-plan/folders/<folderId>/scenarios/<scenarioId>`

```bash
URL=$(echo "$ARGUMENTS" | awk '{print $1}')
RUN_FLAG=$(echo "$ARGUMENTS" | grep -qw -- "--no-run" && echo "false" || echo "true")
PROJECT_ID=$(echo "$URL" | grep -oE 'projects/[0-9]+' | grep -oE '[0-9]+')
FOLDER_ID=$(echo "$URL" | grep -oE 'folders/[0-9]+' | grep -oE '[0-9]+')
SCENARIO_ID=$(echo "$URL" | grep -oE 'scenarios/[0-9]+' | grep -oE '[0-9]+')
echo "PROJECT_ID=$PROJECT_ID FOLDER_ID=$FOLDER_ID SCENARIO_ID=$SCENARIO_ID RUN_FLAG=$RUN_FLAG"
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

## Discover the test project's real conventions

Before writing any file, determine what test-running setup this project
actually has — never assume this plugin's own default scaffold is what's
in place.

### Step 1 — check for `/init existing`'s docs first

```bash
ls .claude/docs/coding-conventions.md .claude/docs/structure.md \
   .claude/docs/test-case-template.md .claude/docs/selectors-locators.md \
   .claude/docs/patterns.md 2>/dev/null
```

Any of these exist → read them. Extract: the language/framework in use,
the real feature-file directory, the real page/screen-object directory and
file extension, the real locator directory and format (a TS/JS factory
function vs. a JSON file vs. something else), and the real step-definition
directory, file extension, module system (CommonJS `require` vs ESM
`import`), and Cucumber binding source (`@wdio/cucumber-framework`,
`playwright-bdd`, `@cucumber/cucumber`, or something else). Then, using
the directory/format described, open 1-2 real files at those paths (one
`.feature` file, one page/screen object, one locator file, one step-
definition file, if each exists) to confirm the exact format before
generating anything — the docs describe the convention, but the real file
is the source of truth if they disagree. Skip Step 2 entirely and go to
Step 3.

### Step 2 — direct repo inspection (only if Step 1 found nothing)

```bash
cat package.json 2>/dev/null | grep -A5 '"scripts"'
cat package.json 2>/dev/null | grep -iE 'cucumber|wdio|playwright|webdriverio'
ls wdio.conf.js wdio.conf.ts cucumber.js .cucumberrc playwright.config.ts 2>/dev/null
find . -maxdepth 4 -name "*.feature" -not -path "*/node_modules/*" 2>/dev/null
find . -maxdepth 4 -type d \( -iname "steps" -o -iname "step-definitions" \) -not -path "*/node_modules/*" 2>/dev/null
find . -maxdepth 4 -type d \( -iname "pages" -o -iname "screens" \) -not -path "*/node_modules/*" 2>/dev/null
find . -maxdepth 4 -type d -iname "locators" -not -path "*/node_modules/*" 2>/dev/null
```

Any signal found (a real `.feature` file, a real page/screen/locator/step-
definition directory, a recognizable test script/dependency) → read 1-2
real files at the discovered paths (one `.feature` file, one page/screen
object, one locator file, one step-definition file, if each exists) to
ground the exact language, naming, module system (CommonJS `require` vs
ESM `import`), and Cucumber binding source (`@wdio/cucumber-framework`,
`playwright-bdd`, `@cucumber/cucumber`, or something else) before
generating anything.

### Step 3 — set the convention variables

- Steps 1-2 both found nothing → `CONVENTION=default`. Use this plugin's
  own scaffold conventions: `FEATURE_DIR=features`,
  `PAGE_DIR=pages` (`pages/mobile` for mobile, `api-clients` for backend),
  `PAGE_EXT=ts`, `LOCATOR_DIR=locators` (`locators/mobile` for mobile),
  `LOCATOR_FORMAT=ts-factory`, `STEP_DIR=steps` (`steps/mobile` for
  mobile), `STEP_EXT=ts`, `STEP_MODULE_SYSTEM=esm`,
  `CUCUMBER_BINDING=playwright-bdd` (frontend/backend) or
  `@wdio/cucumber-framework` (mobile). This is the `/init new` greenfield
  case — behavior is unchanged from before this fix.
- Step 1 or 2 found a real signal → `CONVENTION=discovered`. Set
  `FEATURE_DIR`, `PAGE_DIR`, `PAGE_EXT`, `LOCATOR_DIR`, `LOCATOR_FORMAT`,
  `STEP_DIR`, `STEP_EXT`, `STEP_MODULE_SYSTEM`, `CUCUMBER_BINDING` from
  what was actually read. If only some of these were evidenced (e.g.
  a real feature directory was found but no locator file/directory
  anywhere), best-effort fill the ungrounded piece with the closest
  default shape for the discovered language (e.g. a JS project with no
  locator convention found → a plain exported JS object, not a TS factory
  function) — do not stop to ask the user. This is the one place in this
  command that infers rather than asking; it does not extend to selector
  wording, real selectors, real endpoints, or business content, which are
  still never guessed.

## Resolve the grounding/selector source

Branch on `PLATFORM`:

**`backend`** — no selector step. Use `specs/*/spec.md` and/or
`.claude/docs/backend/` content directly for business-logic grounding in
the spec.md write below. Set `SELECTOR_SOURCE=not-applicable`. Skip
straight to "Write/update spec.md".

**`mobile`**:
```bash
grep -n "^## mobile — " .claude/CLAUDE.md 2>/dev/null
```
- A `## mobile — <SAVED_PATH>` entry found:
  ```bash
  test -d "<SAVED_PATH>" -a -r "<SAVED_PATH>" && echo OK
  ```
  - `OK` → resolve the real source file for this scenario's screen:
    ```bash
    grep -iA1 "^### .*$(echo "$MODULE" | tr -d '-')" .claude/docs/mobile/screens.md 2>/dev/null
    ```
    Match `MODULE` against `screens.md` headings case-insensitively,
    ignoring `-`/spaces (e.g. `MODULE=login-screen` matches
    `### LoginScreen`). A match with a `**File:**` line:
    - The file still exists at `<SAVED_PATH>/<recorded relative path>` →
      open and read it directly, extracting current selector values from
      the real file. Set `SELECTOR_SOURCE=source`. Skip straight to
      "Verify step wording".
    - The file no longer exists at that path (renamed/moved/deleted since
      the last scan) → treat as no match, continue below.
    No match (no `screens.md` for this path, no entry for `MODULE`, or its
    recorded file is gone) → fall back to a direct search:
    ```bash
    find "<SAVED_PATH>" -type f -iname "*$(echo "$MODULE" | tr '-' '*')*" -not -path '*/node_modules/*' -not -path '*/build/*' -not -path '*/.gradle/*' 2>/dev/null
    ```
    - Exactly one match → open and read it directly. Set
      `SELECTOR_SOURCE=source`. Skip straight to "Verify step wording".
    - Zero or 2+ matches → print whatever candidates were found (if any),
      then ask: "Couldn't find a unique real source file for `<MODULE>`
      under `<SAVED_PATH>`. Paste the real file path, or reply `skip` to
      use the scanned docs / live connection instead." Wait for the
      reply. A path given → open and read it directly,
      `SELECTOR_SOURCE=source`, skip straight to "Verify step wording".
      `skip` → continue to the legacy ask below.
  - No `OK` (missing/unreadable) → continue to the legacy ask below.
- No `## mobile — ` entry found → continue to the legacy ask below.

Legacy ask (only reached when the saved path is missing/unreadable, or the
user replied `skip` above):
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
grep -n "^## frontend — " .claude/CLAUDE.md 2>/dev/null
```
- A `## frontend — <SAVED_PATH>` entry found:
  ```bash
  test -d "<SAVED_PATH>" -a -r "<SAVED_PATH>" && echo OK
  ```
  - `OK` → resolve the real source file for this scenario's component:
    ```bash
    grep -iA1 "^### .*$(echo "$MODULE" | tr -d '-')" .claude/docs/frontend/components.md 2>/dev/null
    ```
    Match `MODULE` against `components.md` headings case-insensitively,
    ignoring `-`/spaces (e.g. `MODULE=login-form` matches `### LoginForm`).
    A match with a `**File:**` line:
    - The file still exists at `<SAVED_PATH>/<recorded relative path>` →
      open and read it directly, extracting current selector values from
      the real file. Set `SELECTOR_SOURCE=source`. Skip straight to
      "Verify step wording".
    - The file no longer exists at that path (renamed/moved/deleted since
      the last scan) → treat as no match, continue below.
    No match (no `components.md` for this path, no entry for `MODULE`, or
    its recorded file is gone) → fall back to a direct search:
    ```bash
    find "<SAVED_PATH>" -type f -iname "*$(echo "$MODULE" | tr '-' '*')*" -not -path '*/node_modules/*' -not -path '*/build/*' -not -path '*/dist/*' 2>/dev/null
    ```
    - Exactly one match → open and read it directly. Set
      `SELECTOR_SOURCE=source`. Skip straight to "Verify step wording".
    - Zero or 2+ matches → print whatever candidates were found (if any),
      then ask: "Couldn't find a unique real source file for `<MODULE>`
      under `<SAVED_PATH>`. Paste the real file path, or reply `skip` to
      use the scanned docs / live connection instead." Wait for the
      reply. A path given → open and read it directly,
      `SELECTOR_SOURCE=source`, skip straight to "Verify step wording".
      `skip` → continue to the legacy ask below.
  - No `OK` (missing/unreadable) → continue to the legacy ask below.
- No `## frontend — ` entry found → continue to the legacy ask below.

Before falling back to the legacy ask, check for `locators.md` entries for
this module:
```bash
ls .claude/docs/frontend/locators.md 2>/dev/null
grep -i "$(echo "$MODULE" | tr '-' '.')" .claude/docs/frontend/locators.md 2>/dev/null
```
A match found → use the locator entries from `locators.md` for this module
as the grounding source. Set `SELECTOR_SOURCE=scanned`. Skip the legacy ask
entirely and proceed to "Verify step wording".
No match → continue to the legacy ask below.

Legacy ask (only reached when the saved path is missing/unreadable, or the
user replied `skip` above):
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
message), compare it against the resolved source (the real source file's
content when `SELECTOR_SOURCE=source`, scanned docs' recorded text, or the
live snapshot/DOM). If the real wording differs from CucumberStudio's, use
the REAL wording in the generated feature and note the discrepancy for the
final report. If `SELECTOR_SOURCE=none`, skip this verification entirely —
every step's wording is used as-is from CucumberStudio, and the generated
feature will carry the "unverified" marker.

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

Check whether `$FEATURE_DIR/<MODULE>.feature` already exists (`ls
"$FEATURE_DIR" 2>/dev/null | grep -i "$MODULE"`). Already exists → append
the new `Scenario:` block under the existing `Feature:` header, merging
in (never overwriting or rewriting) any existing `Scenario:` blocks —
same "merge, never overwrite" rule already applied to every other
generated artifact in this command. Missing → write it fresh
(`$FEATURE_DIR` from "Discover the test project's real conventions"
above):

```gherkin
# Source: CucumberStudio — <cucumberstudio-url>
<UNVERIFIED-MARKER-LINE-IF-APPLICABLE>

Feature: <scenario/folder title>

  # AC1: <...>
  Scenario: <scenario title>
    Given <...>
    When <...>
    Then <...>
```

If `SELECTOR_SOURCE=none` (from "Resolve the grounding/selector source"),
the first line after the Source comment must be exactly:
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

### Synchronization waits (anti-flakiness)

Applies to ALL platforms — frontend, mobile, and backend. Core
principle: when a generated step must act on or assert something that
only becomes ready after a transition, wait for it. **Prefer waiting on
an observable readiness condition when one is available; a
fixed-duration wait (pause/sleep/`waitForTimeout`) remains a valid,
allowed fallback when there is no observable condition or no real wait
primitive to use.** This refines — does not repeal — "never invent a
wait step that doesn't already exist": see rule 3.

**Trigger — narrowly scoped to avoid step bloat.** Wait only after a
step that genuinely changes state and leaves something not-yet-ready:
a navigation or redirect, a login success, a request/response that
changes what is rendered or stored, an app dismiss/close/reopen, an
async job whose result the next step reads. Never after a step that
leaves things in the SAME state (filling a text field, selecting an
option, scrolling, building a request body) — most steps in a typical
scenario are this kind and must NOT get a wait.

1. **Prefer an observable condition over a fixed-duration wait, WHEN
   one is available.**
   - *Frontend (Playwright)*: rely on the framework's built-in
     auto-waiting; where an explicit wait is genuinely needed, express
     it as a visibility/state assertion or a `waitFor` (e.g.
     `expect(locator).toBeVisible()`).
   - *Mobile (Appium/WebdriverIO)*: use a "wait for element
     `<locator>` to be displayed" step backed by the project's real
     `waitForDisplayed` primitive.
   - *Backend*: poll for the real state/response —
     retry-until-condition with a timeout. (The MailHog "poll every 2s
     up to 30s" retrieval below is an example of this shape.)
2. **A fixed-duration wait is still allowed and correct** when there is
   genuinely no observable condition to wait on, or the project has no
   real wait primitive to reuse or wrap — e.g. an unavoidable
   animation/settle, or a transition with no stable element or response
   to key off. Keep it as short as is reliable. **Never rip out an
   existing pause just to avoid pauses** — replace one only when a real
   observable wait is actually available.
3. **Reuse before adding.** If the project already has a readiness-wait
   step or helper, use it. If it does NOT, but the project HAS a real
   underlying wait primitive (a driver `waitForDisplayed` /
   `waitForSelector`, an assertion helper, a polling util), you MAY add
   ONE thin, cross-platform binding that delegates to it. Wrapping a
   real primitive is NOT "inventing" a wait; fabricating a wait with no
   backing primitive still is — in that case fall back to a fixed pause
   (rule 2) rather than inventing.
4. **Never key a wait on a platform-specific signal for cross-platform
   content** (e.g. an Android-only `clickable` attribute). Choose a
   condition that holds on every platform the feature runs on, or fall
   back to a fixed pause.
5. **Prefer a specific readiness condition** ("this control is
   present/visible", "this response arrived") over a coarse one
   ("spinner gone", "page loaded") when the intent is that a specific
   thing is ready — a preference, not a requirement.
6. **No redundant blind pause.** Do not emit a fixed pause before an
   action/assertion whose own step already waits internally (many
   tap/click/assert steps auto-wait). This is about redundancy, not
   about banning pauses in general.
7. **`@app_reset` (cold-start) scenarios are the riskiest** — apply
   this strictly right after a login step and right after an app-reopen
   step; a cold-start round-trip is slower and more variable than a
   warm one, and default element-wait timeouts are more likely to be
   exceeded.
8. **One-directional internal consistency, never retroactive.** If a
   NEW scenario being generated performs the same state-changing action
   as an EXISTING scenario already present in the same feature file
   that already waits after it, the new scenario waits too. Never
   rewrite or retrofit an existing scenario's content to add this —
   only new/merged content follows this rule.
9. **Wait before a negative ("not displayed"/"absent") assertion that
   follows a dismissing action** (Skip/Proceed/close/cancel) — the
   transition must complete before the negative assertion, same as the
   general case.

**Idempotency**: never insert a duplicate wait — if one already exists
immediately between the state-changing action and the next
verify/action (from the original CucumberStudio wording, a prior merge,
or an already-present scenario read for rule 8), do not add a second.

**Ambiguity**: the discovered project has more than one candidate
readiness-wait step name used inconsistently across features → ask the
user once which to standardize on for this module, same "ask once when
ambiguous" pattern used elsewhere in this command.

Every readiness-wait step or fixed pause added/used this way is a
technical/no-business-meaning addition — list it under "Steps
auto-supplemented" in the Report, the same field "Automation-only
technical preconditions" already populates (never a new, separate
reporting category).

## Determine the class name

```bash
CLASS=$(echo "$MODULE" | awk -F'-' '{for(i=1;i<=NF;i++){$i=toupper(substr($i,1,1)) substr($i,2)}}1' OFS='')
# TypeScript class names can't start with a digit — prefix with "M" (for "Module") if they do
[[ "$CLASS" =~ ^[0-9] ]] && CLASS="M${CLASS}"
echo "CLASS=$CLASS"
```
(e.g. `user-login` → `UserLogin`; `2fa-login` → `M2faLogin`)

## Re-read the grounding source (no re-fetch, no new live session)

Reuse exactly what "Resolve the grounding/selector source" and "Verify step
wording" already resolved above in this same run — never re-open a
browser/Appium session, never re-ask the user, never re-fetch scanned docs
from scratch.

- `frontend`/`mobile`, `SELECTOR_SOURCE=source` → the already-read content
  of the real source file opened during "Resolve the grounding/selector
  source" — reuse those extracted values directly, never re-open or
  re-read the file.
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

## Check for an existing file for this module

```bash
case "$PLATFORM" in
  frontend|mobile) ls "$PAGE_DIR" "$LOCATOR_DIR" 2>/dev/null | grep -i "$CLASS" ;;
  backend)         ls "$PAGE_DIR" 2>/dev/null | grep -i "$CLASS" ;;
esac
```

`$PAGE_DIR` and `$LOCATOR_DIR` come from "Discover the test project's real
conventions" above — this check runs against the REAL discovered paths,
not a hardcoded default, so it correctly finds an existing file whether
this project uses this plugin's own scaffold or a completely different
one.

If a match is found for this exact module, read that file now — the
generation below merges into it (adds new methods/entries for anything
new, leaves existing ones untouched) rather than overwriting it. If
empty/missing, generate fresh using the convention set by "Discover the
test project's real conventions" above (either the discovered project's
real shape, or this plugin's default TS scaffold).

## Generate the locator/endpoint file

Skip this section for `backend` in the `default` convention — HTTP
method/path stay inline in the API client (see "Generate the page object /
screen object / API client" below), no separate locator file. In the
`discovered` convention, skip it for `backend` too UNLESS discovery found
a real, separate endpoints/registry file for this project (rare, but if
one exists, mirror it the same way frontend/mobile locators are mirrored
below — same "grounded value or explicit TODO marker" rule applies).

Branch on `CONVENTION` (from "Discover the test project's real
conventions" above):

### `CONVENTION=discovered`

Write (or merge new entries into) the file at `$LOCATOR_DIR` for this
module, in `$LOCATOR_FORMAT`, mirroring the exact structure of the real
example file read during discovery (same key naming style, same nesting,
same file-per-module vs. shared-file pattern as the real example). Apply
these content rules regardless of format:
- Selector priority order — frontend/web: `getByRole` → `getByLabel` →
  `getByTestId` → `getByText` → CSS (last resort). Mobile: `accessibility
  id` → `UiSelector.text()`/`NSPredicate` → `resourceId`/class chain →
  `description()` → XPath (last resort).
- Grounded elements (from the resolved selector source) get a real
  selector value in whatever shape the discovered format uses (a locator
  call, a plain string, a JSON value). Ungrounded elements get an explicit
  marker in that same format instead — never invent a plausible-looking
  selector. For a JSON locator file (no comment syntax), use a literal
  string value like `"TODO: unverified — <element description>"` in place
  of a real selector value.
- If a file already exists for this module, add new entries for any new
  element referenced by the feature file; leave existing entries
  untouched.

### `CONVENTION=default`

**`frontend`** — write (or merge new entries into) `$LOCATOR_DIR/<MODULE>.locators.ts`:

```typescript
import { Page } from '@playwright/test';

export const get<CLASS>Locators = (page: Page) => ({
  <elementName>: page.<real-locator-call>,
  // ^ grounded — built from the resolved scanned-docs entry or live snapshot
  <otherElementName>: undefined as any, // TODO: unverified — <element description>
});
```

Selector priority order: `getByRole` → `getByLabel` → `getByTestId` →
`getByText` → CSS (last resort). One entry per UI element referenced by a
step in `$FEATURE_DIR/<MODULE>.feature`. Grounded elements get a real
locator call; ungrounded elements get a `// TODO: unverified —
<description>` comment instead — never invent a plausible-looking
selector.

**`mobile`** — write (or merge new entries into) `$LOCATOR_DIR/<MODULE>.locators.ts`:

```typescript
export const get<CLASS>Locators = () => ({
  <elementName>: '~<real-accessibility-id>',
  // ^ grounded — Android/iOS accessibility id from scanned docs or live inspection
  <otherElementName>: '', // TODO: unverified — <element description>
});
```

Android/iOS priority order: `accessibility id` →
`UiSelector.text()`/`NSPredicate` → `resourceId`/class chain →
`description()` → XPath (last resort).

If a locators file already exists for this module, add new entries for any
new element referenced by the feature file; leave existing entries
untouched.

### Cross-platform locator-key parity check (mobile, discovered convention only)

Applies only when ALL of: `PLATFORM=mobile`, `CONVENTION=discovered`, and
`$LOCATOR_DIR` contains exactly 2 files whose names contain `android` and
`ios` (case-insensitive) — the platform-split signal. In every other case
(frontend, backend, default convention, a single combined mobile file,
more/fewer than 2 matching files), skip this subsection entirely — no
prompt, no Report line beyond "not applicable".

```bash
ls "$LOCATOR_DIR" | grep -i "android"
ls "$LOCATOR_DIR" | grep -i "ios"
```

3+ files match this naming pattern (e.g. a stray backup file) → ambiguous
which 2 are the real pair, skip this subsection entirely rather than
guessing.

Read the current module's key set from both files (everything nested
under the module's own top-level key, e.g. `loginPage`, in both files —
not just the keys added in this run, so a pre-existing asymmetry from an
earlier session is also caught) and diff them.

- A key present in both → no output, no prompt.
- A key present in only one → ask immediately: `"<key>" exists only in
  <platform>.json for this module — is that intentional (platform-
  specific element), or did generation miss the other platform?` Wait for
  the reply.
  - Intentional → record as a deliberate platform-only key. No file
    write.
  - Missing → generate the entry for the missing platform now, using the
    exact same sourcing rules as above (a real grounded value from the
    resolved selector source if available, else the same `"TODO:
    unverified — <element description>"` marker — never invent a
    plausible-looking selector). Merge it into that file (never overwrite
    the whole file).
  - Reply is ambiguous or declined → ask once more; still ambiguous →
    record it as unresolved platform-specific and note the ambiguity in
    the Report, rather than writing an unsolicited entry.
- Never re-ask about a key that already exists in both files with the
  same name — this check is purely about asymmetry, not selector-value
  correctness.

## Generate the page object / screen object / API client

Branch on `CONVENTION` (from "Discover the test project's real
conventions" above):

### `CONVENTION=discovered`

Write (or merge new methods into) the file at `$PAGE_DIR` for this module,
using `$PAGE_EXT`, mirroring the exact shape of the real example file read
during discovery: same base-class/inheritance pattern (or lack of one) if
the example extends something, same import style, same method/function
style (class methods vs. plain exported functions — follow what's real),
same locator-import pattern (import from `$LOCATOR_DIR`, never inline a
raw selector directly here regardless of language). Apply these content
rules regardless of language:
- Methods represent a semantic action or assertion, grouping the Gherkin
  step(s) that describe it — NOT a rigid one-method-per-step-line mapping
  (backend/API calls are the exception: one method per endpoint, since
  that's already a natural 1:1 unit).
- If the file already exists for this module, add new methods for any new
  Gherkin step/endpoint; leave existing methods untouched.

### `CONVENTION=default`

**`frontend`** — write (or merge new methods into) `pages/<CLASS>Page.ts`:

```typescript
import { Page, Locator, expect } from '@playwright/test';
import { BasePage } from './BasePage';
import { get<CLASS>Locators } from '../locators/<MODULE>.locators';

export class <CLASS>Page extends BasePage {
  readonly <elementName>: Locator;

  constructor(page: Page) {
    super(page);
    const loc = get<CLASS>Locators(page);
    this.<elementName> = loc.<elementName>;
  }

  async <actionMethodName>(/* params from the Gherkin step(s) */): Promise<void> {
    // implementation using this.<elementName>
  }

  async expect<AssertionName>(/* params */): Promise<void> {
    // assertion using this.<elementName> and expect()
  }
}
```

Rules:
- Extend `BasePage` from `pages/BasePage.ts`.
- Import locators from `locators/<MODULE>.locators.ts` — never inline a raw
  selector directly in the page object.
- Methods represent a semantic action or assertion, grouping the Gherkin
  step(s) that describe it — NOT a rigid one-method-per-step-line mapping.
  (e.g. a single `login(email, password)` method may implement "When I
  enter my email" + "And I enter my password" + "And I click Sign In" if
  the feature phrases login across separate steps.)
- All `Locator` properties `readonly`, typed `Locator`.
- If the page object already exists for this module, add new methods for
  any new Gherkin step; leave existing methods untouched.

**`mobile`** — write (or merge new methods into) `pages/mobile/<CLASS>Screen.ts`:

```typescript
import { get<CLASS>Locators } from '../../locators/mobile/<MODULE>.locators';

export class <CLASS>Screen {
  private readonly locators = get<CLASS>Locators();

  async <actionMethodName>(/* params */): Promise<void> {
    // implementation using $(this.locators.<elementName>)
  }

  async expect<AssertionName>(/* params */): Promise<void> {
    // assertion using expect($(this.locators.<elementName>))
  }
}
```

Same grouping rule as frontend — one method per semantic action/assertion,
not per literal step line. No `page` fixture; element access is
WebdriverIO's `$('~...')` built from the locator factory above. If the
screen object already exists for this module, add new methods for any new
step; leave existing methods untouched.

**`backend`** — write (or merge new methods into) `api-clients/<CLASS>Client.ts`:

```typescript
import { APIRequestContext, APIResponse } from '@playwright/test';

export class <CLASS>Client {
  constructor(private readonly request: APIRequestContext) {}

  async <endpointMethodName>(/* params from the request shape */): Promise<APIResponse> {
    return this.request.<get|post|put|delete>('<real-path-from-api-contracts.md>', {
      data: { /* real request shape, if any */ },
    });
  }
}
```

Unlike UI actions, one endpoint call is already a natural 1:1 unit with a
Gherkin step — one method per endpoint referenced by the feature's steps.
Method name/HTTP verb/path/request shape come from the grounded source
(`.claude/docs/backend/api-contracts.md` or `spec.md`); when no concrete
endpoint shape is available for a referenced call, write the method with
`// TODO: endpoint contract not found — verify against real backend code`
instead of inventing a plausible-looking path. If the client already
exists for this module, add new methods for any new endpoint; leave
existing methods untouched.

## Generate step definitions

For each Given/When/Then line in `$FEATURE_DIR/<MODULE>.feature` (from
"Generate the feature file"), normalize `{string}`/`{int}` placeholders
the same way Cucumber does, then check `$STEP_DIR` for an existing file
covering this module:

```bash
ls "$STEP_DIR" 2>/dev/null | grep -i "$CLASS"
```

- A matching file exists → read it. A step already bound there → skip it,
  leave the existing binding untouched. Only steps NOT already bound are
  generated below.
- No matching file, or it exists but doesn't cover a given step → generate
  a binding for it, per "Sourcing each binding" below.

### Automation-only technical preconditions (narrow exception)

CucumberStudio scenarios are sometimes written for manual testing and may
omit a precondition a human tester does implicitly (e.g. "Given I am on
the Login screen" before a data-entry step). You may add such a step ONLY
when it is a pure technical/navigation precondition carrying no new
business meaning — never a new or reworded Given/When/Then with
acceptance-criteria significance. List every step added this way under
"Steps auto-supplemented" in the Report. This is the one narrow, always-
reported exception to "never invent scenario steps" (see Rules).

### Sourcing each binding

A step whose real wording mentions OTP / verification code / email code is
sourced differently — see "MailHog OTP retrieval" below instead of the
locator-lookup flow that follows.

For each element/action a step references, look up the entry in
`$LOCATOR_DIR` (written in "Generate the locator/endpoint file"):

- **Grounded** (a real selector value, not a `TODO: unverified` marker)
  → write a binding that delegates to the page object / screen object /
  API client method generated in "Generate the page object / screen
  object / API client" for that element/action. Never inline a raw
  selector in the step body.
- **Not grounded** (missing entry, or still a TODO-stub) → the binding
  cannot be honestly written. Emit a TODO-stub binding instead —
  syntactically valid, but it throws a descriptive error instead of doing
  anything:

```javascript
Given('...', async () => {
  throw new Error('TODO: unverified — locator "<key>" not found in <LOCATOR_DIR>/<MODULE>.locators.<ext>. Run /scan-source or ground manually, then re-run /do-cucumber-task.')
})
```
List this step under "TODO stubs remaining" in the Report — the same
field Phase C already populates for locators; step-def stubs are added to
that same list, not a separate one.

### MailHog OTP retrieval

Applies only when a step's real CucumberStudio wording mentions OTP /
verification code / email code — no inference beyond that wording.

**Search for an existing helper first.** Search `$PAGE_DIR` only (the
reusable method layer — never `$STEP_DIR`: an existing step binding there
is tied to its own exact step text and is already handled by "Generate
step definitions"'s outer already-bound check above, not a candidate
"helper to reuse" for a NEW step with different wording; including
`$STEP_DIR` here would surface that binding's own call site as a false
second match every time one already exists, exactly what happens against
this repo's own `sample/infinity-mobile-test-automation` project) for a
method whose name contains both `OTP` and `MailHog`/`Mailhog`
(case-insensitive), or a call site matching a MailHog API path
(`/api/v2/search` or `/api/v2/messages` against a host containing
`mailhog`):
```bash
grep -rniE "mailhog" --include="*.js" --include="*.ts" "$PAGE_DIR" 2>/dev/null | grep -iE "otp|api/v2"
```
- **Exactly one match** → reuse it: wire the new step definition to call
  that existing method directly. Never generate a new API client method,
  extraction method, or duplicate step — this is the same "never
  duplicate, always reuse" rule already applied to locators and step
  bindings elsewhere in this command.
- **More than one match** (ambiguous which to reuse) → ask the user which
  one to wire the new step to, same "ask once when ambiguous" pattern used
  elsewhere in this command.
- **No match** → scaffold new, below.

**Scaffolding new** (only when nothing to reuse):

1. **Resolve `MAILHOG_BASE_URL`**: check the project's existing shared
   config file (the same file conventions like `${AUTH0_BASE_URL}` already
   live in) for a `MAILHOG_BASE_URL` entry. Not found → ask the user once
   ("What is this project's MailHog base URL?"), write it into that same
   config file so a later run in the same project never asks again.
2. **API client method** — `GET ${MAILHOG_BASE_URL}/api/v2/search?kind=to&query=<real recipient email>`.
   The recipient email must come from real test data/fixtures/scenario
   content — never invent it, same grounding rule as everything else this
   command generates.
3. **Extraction method** — from the search response, sort matching items
   by timestamp descending (never assume the API's return order is
   already sorted — MailHog does not expire old messages, so a stale
   match from an earlier test run may otherwise be picked by mistake),
   take the newest, extract the OTP via `\b\d{6}\b` against
   `Content.Body` (a 6-digit numeric code is the default OTP shape — if
   the scenario's real wording implies a different code shape, ground the
   regex in that wording instead).
4. **Step definition** — `"I get OTP code from mailhog and assign to
   {string}"` (the real wording already found in use in this codebase's
   MailHog convention) — calls the extraction method, sets the Gherkin
   variable using the same variable-assignment convention already used by
   other step bindings in this project.

**Retry/timing**: MailHog may not have received the email yet at query
time. Poll every 2 seconds, up to 30 seconds total, before treating it as
"no matching email found" — a real, reported failure, never a guessed
OTP.

Record for the Report: whether an existing helper was reused (and its
path) or a new one was scaffolded (and the `MAILHOG_BASE_URL` used).

### Format

Branch on `CONVENTION` (from "Discover the test project's real
conventions"):

**`CONVENTION=discovered`** — mirror the real step-def file read during
discovery: same import style, same `$STEP_MODULE_SYSTEM` (`require` vs
`import`), same function declaration style (arrow vs `async function`),
same `$CUCUMBER_BINDING` syntax, same page/screen/client instantiation
pattern.

**`CONVENTION=default`**:

`frontend`/`backend` (`playwright-bdd`) — write (or merge new bindings
into) `$STEP_DIR/<MODULE>.steps.ts`:

```typescript
import { createBdd } from 'playwright-bdd';
import { <CLASS>Page } from '../pages/<CLASS>Page';

const { Given, When, Then } = createBdd();

Given('<step text>', async ({ page }) => {
  const <instanceName> = new <CLASS>Page(page);
  await <instanceName>.<actionMethodName>();
});
```

`mobile` (`@wdio/cucumber-framework`) — write (or merge new bindings
into) `$STEP_DIR/<MODULE>.steps.ts`:

```typescript
import { Given, When, Then } from '@wdio/cucumber-framework';
import { <CLASS>Screen } from '../../pages/mobile/<CLASS>Screen';

const <instanceName> = new <CLASS>Screen();

Given('<step text>', async () => {
  await <instanceName>.<actionMethodName>();
});
```

One binding per step. String parameters use `{string}`, typed `string`;
int parameters use `{int}`, typed `number`.

### Merge

If `$STEP_DIR/<module>Steps.<ext>` (or the real discovered naming
convention) already exists, add only the new bindings identified above;
leave every existing binding untouched.

### Sanity check

After writing, set `STEP_FILE` to the file just written/merged, then run:
```bash
[ "$STEP_EXT" = "ts" ] && npx tsc --noEmit "$STEP_FILE" || node --check "$STEP_FILE"
```
A parse error → fix it now, re-run the check until it's clean, before
ending this section.

## Discover the real test-run command

"Discover the test project's real conventions" earlier only captured
feature/page/locator/step-def layout — it never looked up a test-run
command or runner-config path. Look it up now, once, regardless of
`RUN_FLAG` — this is a cheap, read-only lookup, not the smoke test itself,
and the Report always shows the result so the user knows how to run the
feature themselves even when `--no-run` was used:

```bash
cat package.json 2>/dev/null | grep -A10 '"scripts"'
ls wdio.conf.js wdio.conf.ts playwright.config.ts 2>/dev/null
```

### Mobile cross-platform detection

If `PLATFORM=mobile`, before falling back to the generic lookup above,
resolve EACH platform independently — a plain config existing for one
platform does not mean the other platform is absent, it may just use a
suffixed-only naming convention, so both must be checked on their own
merits, not inferred from the other's result:

```bash
ls wdio.ios.conf.js 2>/dev/null || find . -maxdepth 1 -name "wdio.ios*.conf.js" 2>/dev/null
ls wdio.android.conf.js 2>/dev/null || find . -maxdepth 1 -name "wdio.android*.conf.js" 2>/dev/null
```
(the fallback uses `find -name` rather than a bare shell glob — under zsh,
an unquoted glob that matches nothing aborts word-expansion and prints
`zsh: no matches found` even with `2>/dev/null`, since that's a shell
parse-time error, not the command's own stderr; `find -name` takes the
pattern as a literal argument and matches internally, so it stays silent
and clean when nothing matches. This is the same class of zsh-glob
sandbox quirk documented in this plan's Global Constraints.)

For each platform:
- Plain file (`wdio.<platform>.conf.js`) exists → use it directly.
- Plain file missing, but suffixed variants exist (e.g.
  `wdio.androidci.conf.js`, `wdio.androidemulators.conf.js`) → ask once
  for that platform: "Multiple <platform> wdio configs found: <list>.
  Which one should /do-cucumber-task use? Reply with the filename." Wait
  for the reply, then treat the reply as if it were that platform's
  plain config file for the rest of this command.
- Neither plain nor any suffixed variant exists → that platform has no
  config at all.

Combine both platforms' results:
- Both resolved (plain file or user-chosen suffixed variant) →
  `PLATFORMS_TO_RUN="ios android"` (this exact order — iOS always runs
  before Android in every later section, never the reverse, never in
  parallel). Resolve `RUN_COMMAND_IOS` and `RUN_COMMAND_ANDROID`
  independently, each filtered to the freshly-generated feature the same
  way as "Resolve each RUN_COMMAND" below.
- Only one resolved → `PLATFORMS_TO_RUN` is that single platform; resolve
  the one corresponding `RUN_COMMAND_<PLATFORM>`.
- Neither resolved at all → fall through to the generic lookup above as
  a single-config case (unchanged from before this round;
  `PLATFORMS_TO_RUN` is unset, the rest of this command behaves exactly
  as it did before this round).

### Resolve each RUN_COMMAND

For each config resolved above (one for non-mobile or single-platform
mobile, or two for iOS+Android), identify the real test script (e.g.
`test`, `test:mobile`) from the `scripts` block, and filter the config to
just the freshly-generated feature:
- The config supports `--spec=<path>` → use
  `--spec=$FEATURE_DIR/<MODULE>.feature`.
- It doesn't → use `--tags=@<MODULE>` (the Scenario generated in "Generate
  the feature file" carries an `@<MODULE>` tag for exactly this purpose;
  add it there now if this section finds it's missing).
- No real test script/runner config found at all for a resolved config →
  set that `RUN_COMMAND` (or `RUN_COMMAND_<PLATFORM>`) to `not determined
  — no test script or runner config found`.

## Prepare the smoke-run environment (mobile cross-platform only)

Skip this entire section when `RUN_FLAG=false`, or `PLATFORMS_TO_RUN` is
unset (non-mobile, or no platform-specific wdio config was found —
nothing to prepare, "Run smoke test" below handles the single-config case
exactly as before this round). Runs once per platform in
`PLATFORMS_TO_RUN`, in order, immediately before that platform's own
live-verify pass and real smoke-test run below.

### Appium

```bash
curl -s -o /dev/null -w "%{http_code}" http://localhost:4723/status 2>/dev/null
```
(use the real port from the discovered wdio config if it specifies a
non-default one). Response is not `200` → start it in background, no ask
first — this is cheap and low-risk:
```bash
appium > /tmp/appium-<platform>.log 2>&1 &
```
Poll the same status check for a few seconds until it responds, then
proceed.

### Device / emulator

Check whether a device is already booted for this platform (`adb
devices` for Android, `xcrun simctl list devices booted` for iOS). None
booted → ask before booting, this is a heavier and more disruptive action
than starting Appium: "No <platform> device/emulator is booted. Boot the
default device from wdio.<platform>.conf.js (<device name from the
config>)? Reply: yes / no." Wait for the reply.
- `yes` → boot it (the real platform-appropriate command), wait until
  ready.
- `no` → skip this platform for this run, note why in the Report,
  continue to the next platform in `PLATFORMS_TO_RUN`.

### App bundle / APK

Check the app path the discovered config points at exists on disk (e.g.
`data/thanos.apk` for Android, the `.app`/`.ipa` path for iOS). Missing →
skip this platform for this run, note why in the Report (e.g. "Android
skipped — data/thanos.apk not found"), continue to the next platform in
`PLATFORMS_TO_RUN`.

### No teardown

Never stop Appium and never shut down a device/emulator this section
started — not at the end of this run, not on failure, not ever. The user
manages their own environment lifecycle across a session of multiple
`/do-cucumber-task` runs; tearing down here would force an expensive
re-boot on every next invocation.

## Live-verify locators (frontend)

Skip this entire section when `RUN_FLAG=false`, or `PLATFORM` is not
`frontend`, or no live URL can be resolved.

Resolve the live URL in this order:
1. `**Target:**` field in `specs/<NNN>-<MODULE>/spec.md` — read it:
   ```bash
   grep "^\*\*Target\*\*:" specs/*-"$MODULE"/spec.md 2>/dev/null | head -1
   ```
2. `BASE_URL` environment variable: `echo "${BASE_URL:-}"`.
3. Ask the user once: "What is the live URL for this module's page?" Wait
   for reply. A URL given → use it. `skip` replied → skip this section,
   note "live-verify skipped — no URL provided" in the Report.

If Playwright MCP isn't available (`ToolSearch(query: "playwright")` returns
nothing) → tell the user to run `/add-mcp playwright` first, or reply
`skip` to skip this pass. Do not block the run.

**Verify flow** (when URL resolved and Playwright MCP available):

1. Use Playwright MCP to navigate to the resolved live URL.
2. Dump the DOM snapshot.
3. For each locator entry in `$LOCATOR_DIR/<MODULE>.locators.ts` just generated:
   - **Resolves + matches source-grounded value** → no action.
   - **Resolves + different value than source-grounded** → live value wins.
     Update that `$LOCATOR_DIR` entry (merge, never overwrite the whole
     file). Note the correction in the Report. Log to
     `.claude/docs/known-issues.md` under `## Locator drift` with key
     `(locator key, frontend)` using the same entry format as the mobile
     locator-drift logging.
   - **Doesn't resolve at all** → flag clearly in the Report — this
     locator will very likely fail the smoke test. Do not retry or heal
     here; that is the smoke-test heal loop's job.

## Live-verify locators (mobile cross-platform only)

Skip this entire section when `RUN_FLAG=false`, or `PLATFORMS_TO_RUN` is
unset. Runs once per platform in `PLATFORMS_TO_RUN`, in order, for every
platform not skipped in "Prepare the smoke-run environment" above,
immediately before that platform's own "Run smoke test" below.

Source-grounded locators (from "Generate the locator/endpoint file") are
a hypothesis, not a guarantee — the real build may not honor the exact
selector the source code implies. This is a one-shot check against the
real, running app before committing to a full smoke-test run.

Execute the scenario's real Given/precondition steps for real (actual
navigation via the freshly-generated step-defs — this is not a dry run).
Once navigation completes, dump the live UI state (Appium page source)
and check whether every locator this run generated for the CURRENT
platform resolves against it:
- Resolves, and matches the source-grounded value → no action.
- Resolves, but with a DIFFERENT value than source-grounded → the live
  value wins. Update that `$LOCATOR_DIR` entry for this platform (merge,
  never overwrite the whole file) to the live value. Note the correction
  in the Report, and log/update the entry in `.claude/docs/known-issues.md`
  per "Run smoke test"'s "Logging discoveries to known-issues.md"
  subsection — the same rules apply here, keyed on
  `(locator key, platform)`.
- Doesn't resolve at all → flag clearly in the Report (do not silently
  continue as if it were fine) — this locator will very likely fail the
  real smoke-test run below too, but this pass does not retry or heal it;
  that's "Run smoke test"'s job.

This pass is throwaway — it does not share an app/session state with the
actual smoke-test run below. "Run smoke test" starts fresh; the Given
steps run for real again there too. This keeps the two passes
independent and simple to reason about, at the cost of running the
precondition steps twice.

## Run smoke test (optional)

Skip this entire section when `RUN_FLAG=false` (only when `--no-run` was
passed) — use this when no live device/browser/server is available on
this box. `RUN_COMMAND`/`RUN_COMMAND_<PLATFORM>` above was already
resolved regardless of `RUN_FLAG` — only the actual execution below is
gated. When `PLATFORMS_TO_RUN` is set (mobile cross-platform), this
section runs once per platform in `PLATFORMS_TO_RUN`, in order, for every
platform not skipped in "Prepare the smoke-run environment" above; when
it's unset, this section runs exactly once, exactly as before this
round.

### Retry — per unique locator, not per step

Run the filtered command (for `PLATFORMS_TO_RUN` cases, the current
platform's `RUN_COMMAND_<PLATFORM>`).

Two independent budgets apply for the CURRENT platform's run only (an
iOS run and an Android run each get their own full budgets — a
platform's usage never reduces the other's):
- **Per-locator cap:** 3 heal attempts for any single locator.
- **Per-platform cap:** 5 total heal attempts across every locator in
  this platform's run, whichever is hit first stops further healing for
  this platform.

- **Pass** → proceed to "Auto-un-disable the feature" (or the next
  platform in `PLATFORMS_TO_RUN`, if one remains).
- **Fail on a specific step** — read the failure's stack trace and
  extract the file:line it originates from. Compare against the set of
  files THIS run wrote or merged this session (the step-def file from
  "Generate step definitions", the page/screen object from "Generate the
  page object / screen object / API client", the locator file from
  "Generate the locator/endpoint file"):
  - **Inside that set, and it's a locator/element-not-found error:**
    - Re-groundable from a real source (re-read the real file if
      `SELECTOR_SOURCE=source` — it may have changed since the scan — or
      inspect a live app/browser via Appium/Playwright MCP if a live
      connection is available) → update that one `$LOCATOR_DIR` entry
      for the CURRENT platform (merge, never overwrite the whole file),
      retry. This locator's own attempt count goes up by one; so does the
      platform's total.

      **Opportunistic same-screen scan** (live-reground case only, not
      the `SELECTOR_SOURCE=source` re-read case): the same live dump just
      fetched already contains every OTHER element currently rendered on
      this screen. Check every OTHER locator entry belonging to the SAME
      top-level `$LOCATOR_DIR` namespace as the failing one (e.g. the
      same `loginPage` object) against that SAME dump — never fetch a
      new dump, never navigate elsewhere. Only check locators actually
      PRESENT in the dump; an element not currently rendered (hidden,
      conditional, behind an unopened modal) is simply not checked, never
      flagged as broken. Any other same-namespace locator found with a
      DIFFERENT value than what's currently in `$LOCATOR_DIR` gets
      merged into the SAME update as the failing locator's own fix — one
      file write, not a separate one. These opportunistic corrections do
      NOT count against either heal budget (per-locator 3-cap,
      per-platform 5-cap) — only the originally-failing locator's own
      heal does, exactly as before this addition. Record them separately
      in the Report from the primary heal count (e.g. "N other locator(s)
      in the same screen corrected opportunistically: <list>").
      - Platform total reaches 5 → stop the whole platform's run
        immediately, regardless of which locator triggered it — no
        budget remains for any locator this run. Print the runner output
        tail, leave it to the human.
      - Platform total still under 5, but THIS locator's own count
        reaches 3 and it's still failing → stop the whole platform's
        run — this specific locator cannot be healed further within its
        own budget. Print the runner output tail, leave it to the human.
      - Neither cap reached yet → retry this same locator again.

      (A locator that healed successfully within budget doesn't block a
      DIFFERENT locator encountered later in the same run — each new
      locator starts its own fresh 3-attempt count; only the shared
      platform total carries forward across all of them.)
    - `PLATFORM=frontend`, re-grounding via Playwright MCP: check
      availability first:
      ```
      ToolSearch(query: "playwright", max_results: 5)
      ```
      No Playwright MCP found → treat as not re-groundable (hard stop for
      this locator, print runner tail, never guess). Playwright MCP found
      → navigate to the page for this MODULE using the same live URL
      resolved in "Live-verify locators (frontend)" above; if that URL is
      no longer available (session ended), ask once: "What URL should I
      use to inspect <MODULE>?" No answer → hard stop. URL given →
      proceed with inspection, update locator, retry.
    - Not re-groundable (no real source to check) → stop the whole
      platform's run immediately (not counted against either budget — a
      hard stop, not a retry), print the runner output tail, leave it to
      the human. Never guess a replacement selector.
  - **Inside that set, but not a locator error** (timeout, flaky wait,
    generic assertion failure in THIS run's own generated step-def/page-
    object code, etc.) → if the fix is grounded in the real failure
    output (not a guess) and stays within a file this run wrote or
    merged (e.g. lengthening a timeout the failure output shows was too
    short, wrapping a flaky check in a retry), apply it directly to that
    file and retry; otherwise retry unchanged. Either way, counted
    against the platform's total budget only (no single locator to
    attribute it to).
  - **Outside that set** (the failure originates in a file this run did
    NOT write or merge — a pre-existing shared step, base page class, or
    other existing code) → **shared-code-bug flow**, not the locator-heal
    flow above:
    1. Read the specific file:line, describe the bug in plain terms (what
       the code does, why it's failing here).
    2. Ask the user: `Found what looks like a pre-existing bug in
       <file>:<line> — <description>. Reply: a — file it (note in Report
       + tag Scenario @fix_<short-description>), or b — generate a
       Gherkin-only workaround using existing shared steps`. Wait for the
       reply.
    3. **Reply `a`** → record the file/line/description in the Report,
       add an `@fix_<short-description>` tag to the Scenario in
       `$FEATURE_DIR/<MODULE>.feature`, and log/update the entry in
       `.claude/docs/known-issues.md` per "Logging discoveries to
       known-issues.md" below. This platform's run is marked failed — the
       bug is filed, not worked around.
    4. **Reply `b`** → rewrite ONLY the Given/When/Then sequence in
       `$FEATURE_DIR/<MODULE>.feature`, composed entirely from steps that
       already exist elsewhere in the discovered step-def directory (e.g.
       splitting one buggy high-level step into several already-existing
       finer-grained steps, or inserting an existing generic wait step if
       one exists in the shared step library). Never create new step-def
       code, never touch the file with the bug. Then retry this
       platform's run with the rewritten sequence — this retry is NOT
       counted against either heal budget, since no locator was healed;
       it's a one-time structural change. No viable existing-step
       composition exists → automatically fall back to the `a` flow
       above, and tell the user why no workaround could be composed.
    5. Repeat independently if a LATER step in the same scenario also
       hits a shared-code bug.

Record for the Report (per platform): retry counts against each budget,
which locator(s) were healed and from what source, any grounded step-def/
page-object fix applied (file, description), any shared-code bug found
(file:line, description, which option was taken), final pass/fail, and
the failing step + output tail if still failing.

### Cross-platform regression guard (Round 2 re-verify)

Applies only when `PLATFORMS_TO_RUN` is set (mobile cross-platform) —
no-op for a single-platform or non-mobile run.

**Classify every heal from this platform's run** (using the record
already kept above — "which locator(s) were healed and from what
source", any grounded step-def/page-object fix applied, any
shared-code-bug file:line, and the workaround's rewritten Gherkin
sequence):
- **Platform-exclusive**: a heal to the CURRENT platform's own
  `$LOCATOR_DIR` entry, but ONLY when `$LOCATOR_DIR` is platform-split
  (the same 2-file android/ios detection from "Cross-platform locator-key
  parity check") — this cannot affect the other platform.
- **Shared**: everything else a heal can touch — the step-definition
  file, the page/screen object file, a Gherkin-only workaround rewrite
  (it changes the feature file, read by every platform), or the locator
  file itself when `$LOCATOR_DIR` is a single combined file (not
  platform-split).

Add every shared heal from this platform's run to a running
`SHARED_FILES_TOUCHED` list, kept for the whole feature (not reset
between platforms within the same round) — record WHICH platform
contributed each entry (iOS's own heals here matter later only as
Round-2 heals; they never trigger a Round 2 by themselves, since nothing
runs after iOS within Round 1 that could invalidate it — only a LATER
platform's shared heal can do that).

**After the LAST platform in `PLATFORMS_TO_RUN` reaches pass/fail/skip**
(this is "Round 1" — the ordinary sequential loop above, unchanged):
- No entry in `SHARED_FILES_TOUCHED` came from a platform LATER than iOS
  (either the list is empty, every entry is iOS's own, or Android never
  ran at all — skipped or absent from `PLATFORMS_TO_RUN`) → nothing to
  re-verify. Proceed to "Auto-un-disable the feature". (iOS's own Round-1
  heals never need a Round 2 re-check of iOS itself — there is nothing to
  have invalidated it.)
- `SHARED_FILES_TOUCHED` has at least one entry from Android's Round 1
  run AND iOS passed in Round 1 → **Round 2**: re-run iOS only, using
  `RUN_COMMAND_IOS` directly — skip "Prepare the smoke-run environment"
  and "Live-verify locators" again for iOS (its environment and locators
  are unchanged; only shared code changed). Apply the same heal-budget
  rules as Round 1, continuing from iOS's Round 1 counts (a platform's
  5-total and 3-per-locator caps are NOT reset for Round 2 — they
  represent the whole feature's healing effort on that platform, not one
  round's).
  - iOS passes clean in Round 2 (no heal needed, or only a
    platform-exclusive heal) → stable. Proceed to "Auto-un-disable the
    feature" with both platforms' results now mutually consistent.
  - iOS needs a SHARED heal in Round 2 → the 2-round cap is reached. Stop
    immediately — do not attempt a Round 3, do not re-run Android again.
    Report: "cannot stabilize both platforms simultaneously after 2 sync
    rounds — manual intervention needed." Keep `@disable`.
  - iOS fails outright in Round 2 (heal budget exhausted, hard stop) →
    treat iOS as failed for this run.
- Android has a shared heal in `SHARED_FILES_TOUCHED` but iOS did NOT
  pass in Round 1 (already failed/skipped there) → no Round 2 needed;
  iOS's Round 1 result already stands and isn't being invalidated by
  anything new.

Record for the Report: whether Round 2 ran, its outcome, and — if the
2-round cap was hit — which shared file(s) triggered it each time.

### Logging discoveries to `known-issues.md`

Both a shared-code bug filed via the `a` flow above and a live-verify
locator drift correction (see "Live-verify locators (mobile cross-platform only)" and "Live-verify locators (frontend)" above) are logged to
`.claude/docs/known-issues.md`, immediately at discovery time — not
batched to Report time.

If `.claude/docs/` or `known-issues.md` doesn't exist yet, create both
(`mkdir -p .claude/docs` first). If the file already exists but predates
this structure (a legacy file from an older `/init`, with no "Static
scan"/"Shared-code bugs"/"Locator drift" headings at all) — treat its
entire existing content as the "Static scan" section body unchanged, and
append the "Shared-code bugs" and "Locator drift" headings fresh below it,
rather than improvising a different restructuring. The file always has
exactly these three top-level sections, in this order:
```
# Known Issues

## Static scan (from /init)
<untouched by this command — /init's content, or "not determined — /init
has not been run" if the file was just created>

## Shared-code bugs (from /do-cucumber-task)
<entries as below, or "none found yet">

## Locator drift (from /do-cucumber-task live-verify)
<entries as below, or "none found yet">
```

**Shared-code bug entry** (one `###` heading per unique `file:line`):
```
### <short-description> — <file>:<line>
- First seen: <YYYY-MM-DD>
- Description: <what the code does, why it's failing>
- Tag: @fix_<short-description>
- Also seen in: <module> (<platform>)
```
- New `file:line` → append a new `###` entry under "Shared-code bugs".
- Same `file:line` as an existing entry → do NOT create a new entry;
  append `, <module> (<platform>)` to that entry's "Also seen in" line
  instead.

**Locator drift entry** (one `###` heading per unique
`(locator key, platform)` pair):
```
### <locator key> (<platform>)
- First seen: <YYYY-MM-DD>
- Source said: "<original source-grounded value>"
- Live confirmed: "<latest live value>"
- Also seen in: <module> (<YYYY-MM-DD>)
```
- New `(locator key, platform)` pair → append a new `###` entry under
  "Locator drift". "Source said" is fixed to the value seen the first
  time this pair was logged — never changes on a later update.
- Same pair, SAME live value as the existing entry → append
  `, <module> (<YYYY-MM-DD>)` to the existing "Also seen in" line only.
- Same pair, DIFFERENT live value than the existing entry (drifted again)
  → update "Live confirmed" to the new value, leave "Source said"
  untouched, append a brand new "Also seen in" line for this occurrence
  (do not merge it into the prior "Also seen in" line — the separate
  lines preserve the drift history).

Never edit the "Static scan" section — that belongs to `/init`; read past
it to reach the other two sections.

## Auto-un-disable the feature

Read `$FEATURE_DIR/<MODULE>.feature`'s tag line (written in "Generate the
feature file").

- "Generate step definitions" left any TODO-stub binding → keep
  `@disable`, state which step(s) are stubbed and why in the Report.
- `RUN_FLAG=false` and no TODO-stub was left → remove `@disable` (no run
  evidence exists, but nothing is known to be missing either).
- `RUN_FLAG=true`, `PLATFORMS_TO_RUN` unset (non-mobile, or mobile with
  only one platform config) and "Run smoke test" passed (with or without
  heals) → remove `@disable`.
- `RUN_FLAG=true`, `PLATFORMS_TO_RUN` set (mobile cross-platform), EVERY
  platform in `PLATFORMS_TO_RUN` passed this run, AND the "Cross-platform
  regression guard" above found nothing left to re-verify (no Round 2
  needed, or Round 2 ran and passed clean) → remove `@disable`. A
  platform skipped in "Prepare the smoke-run environment" (missing app
  bundle, declined device boot, unresolved config ambiguity) counts the
  same as a failed platform here — it does not count as passed, and does
  not exempt itself from the "every platform" rule.
- The "Cross-platform regression guard" hit the 2-round cap (still
  unstable between platforms) → keep `@disable`, state this explicitly in
  the Report — even though each platform's OWN last run showed a pass,
  the two are not mutually consistent yet.
- Any other case (a locator's or the platform's heal budget exhausted and
  still failing, a hard stop, a shared-code bug filed via the `a` flow,
  or at least one platform in `PLATFORMS_TO_RUN` failed or was skipped) →
  keep `@disable`, state which platform(s) failed/were skipped and why in
  the Report.

## Report

```
Spec: specs/<NNN>-<MODULE>/spec.md
Feature: <FEATURE_DIR>/<MODULE>.feature
Platform: <PLATFORM>
Generation convention: <discovered from existing project (<language>, <FEATURE_DIR>) | default TS/Playwright-bdd/WebdriverIO scaffold>
Selector source: <real source file | scanned docs | live Playwright | live Appium | unverified | not applicable (backend)>
Wording discrepancies fixed: <list, or "none">
Page object / Screen / API client: <path>
Locators: <path, or "not applicable (backend)">
Locator parity: <n>/<total> keys matched | <n> platform-specific (<list, or "none">) | <n> gap(s) fixed (<list, or "none">) | not applicable (not a platform-split mobile project)
Selectors/endpoints grounded: <n>/<total>
TODO stubs remaining: <n> (method/entry/step names listed, or "none")
Step definitions: <path>
Steps generated: <n> new / <n> reused (already covered)
Steps auto-supplemented (technical precondition only): <list, or "none">
Live-verify (frontend only): <n/n locators matched source | n corrected (list) | n unresolved (list) | skipped — no URL available | skipped — Playwright MCP not found | not applicable (non-frontend)>
Smoke run: <not run | passed (n heal attempts: <list>) | failed — <reason: locator cap (3) reached | platform heal-budget (5) exhausted | shared-code bug filed (file:line, @fix_* tag) | hard stop — no source to heal from>: <tail output> | see per-platform breakdown below>
Opportunistic corrections (same screen/page): <n other locator(s) corrected: <list>, or "none">
Feature tag: <@disable removed | @disable kept — reason>
Known issues logged: <n> shared-code bug(s) (<list file:line, or "none">), <n> locator drift(s) (<list key, or "none">)
MailHog OTP: <reused existing helper <path> | scaffolded new (MAILHOG_BASE_URL=<value>) | not applicable>
```

When `PLATFORMS_TO_RUN` was set this run (mobile cross-platform), insert
this breakdown here, before "Run it yourself" below — one line per
category, covering every platform in `PLATFORMS_TO_RUN`:
```
Platforms run: <list, e.g. "iOS, Android (both wdio configs found)">
Environment: <per-platform: Appium state, device/emulator state, or "skipped — <reason>">
Live-verify: <per-platform: n/n locators matched source | n corrected (list) | n unresolved (list)>
Smoke run (per platform): <platform> — passed (n heal attempts) | failed — <reason, incl. shared-code-bug file:line + @fix_* tag if applicable> | skipped — <reason>
Opportunistic corrections (per platform): <platform> — <n other locator(s) corrected: <list>, or "none">
Cross-platform re-verify: not needed (no shared-file heals) | iOS re-verified after Android shared-file heal — passed clean | unstable after 2 rounds — manual intervention needed
```
Omit this breakdown entirely when `PLATFORMS_TO_RUN` was never set — the
single `Smoke run:` line above already covers that case exactly as
before this round.

```
If a discovered convention was used: verify your existing runner config
actually picks up these new files (e.g. its feature-file glob) — this
command does not modify runner configuration.

Run it yourself:
  <RUN_COMMAND, or RUN_COMMAND_IOS and RUN_COMMAND_ANDROID when PLATFORMS_TO_RUN was set>
```

"Run it yourself" is always the last thing printed in this Report — no
narrative summary, heal/fix write-up, or file list belongs after it. If
you want to explain what was healed or which files were touched, put that
content earlier in the Report (e.g. folded into the `Smoke run:`/per-
platform lines above), never appended after "Run it yourself".

## Rules

- Do NOT run `git` commands — this command only reads/writes files and
  calls MCP tools.
- Never guess a module name, platform, selector wording, real selector,
  real endpoint, or a replacement selector while healing a failing smoke
  test — ask when ambiguous, mark "unverified"/TODO-stub when no grounded
  source is available, and stop (never guess) when a failing smoke-test
  step has no real source left to re-ground from.
- Never invent scenario steps not present in the fetched CucumberStudio
  content, with one narrow exception: "Generate step definitions" may add
  a pure technical/navigation precondition step with no business meaning
  (e.g. an implicit "Given I am on the X screen" a manual tester would do
  without writing it down) — never a step carrying acceptance-criteria
  significance. Every such addition is listed under "Steps
  auto-supplemented" in the Report, always.
- Never overwrite an existing page object / screen object / API client /
  locators / step-definitions file wholesale — merge in new
  methods/entries/bindings, leave existing ones untouched.
- Never edit a pre-existing/shared code file to work around a bug found
  during a smoke run — the shared-code-bug workaround only ever rewrites
  this module's own feature file's Given/When/Then sequence using steps
  that already exist; file the bug (Report + `@fix_*` tag) instead of
  patching shared code.
- Never tear down Appium or a device/emulator this command starts during
  a smoke run — the user manages their own environment lifecycle across
  a session of multiple runs.
- A live-verify locator check that resolves to a different value than the
  source-grounded one is a real grounding source, not a guess — prefer it
  and update the locator file; a locator that doesn't resolve at all is
  flagged, never silently accepted.
- A shared-code bug filed (option a) or a live-verify locator drift is
  always logged to `.claude/docs/known-issues.md` (creating it and its
  parent directory if missing, updating the matching entry if the same
  file:line / locator+platform was seen before) — never a duplicate entry
  for something already tracked.
- Convention discovery (language, directory, locator file format, step-
  definition layout) uses best-effort matching from real existing files
  when found — this is the one place this command infers rather than
  asking. It does NOT apply to selector wording, real selectors, real
  endpoints, or business content, which are still never guessed.
- A step requiring OTP retrieval always searches for an existing
  MailHog+OTP helper before scaffolding a new one — never duplicate an
  existing API client method, extraction method, or step binding. Never
  invent a recipient email, MailHog base URL, or OTP code shape; ask once
  when genuinely missing/ambiguous.
- A heal applied while fixing a later platform (Android) that touches
  shared code always triggers a Round 2 re-verify of any earlier platform
  (iOS) that already passed — a mobile cross-platform feature is never
  marked done from one platform's pass alone if shared code changed
  afterward. Capped at 2 rounds total; still-unstable after that is a
  reported failure, never a silent pass.
- Synchronization waits apply on every platform (frontend, mobile,
  backend) and only after a step that genuinely changes state and
  leaves something not-yet-ready — never after one that leaves things
  in the same state. Prefer an observable readiness condition when one
  is available; a fixed-duration pause is still valid when there is no
  observable condition or no real wait primitive to reuse or wrap, and
  an existing pause is never removed just to avoid pauses. Reuse an
  existing readiness-wait step, or add at most ONE thin binding that
  delegates to a real underlying primitive — a wait with no backing
  primitive is still invented and must not be fabricated. Every wait or
  pause added/used this way is counted under "Steps auto-supplemented"
  in the Report, the same field used for every other technical/
  no-business-meaning step addition.
- The smoke run is on by default now — if it fails and no live
  device/browser/server was ever reachable this run (Appium/emulator/
  server connection refused or timed out before any real test step ran),
  say so plainly in the Report and point the user at `--no-run` for
  future invocations on this box, instead of only printing a raw runner
  failure tail that leaves the real cause unclear.

---
name: do-cucumber-task
description: Fetch one CucumberStudio scenario, ground it against this workspace's spec.md/scanned-source knowledge, verify its wording against real selectors when available, write/update specs/NNN-<module>/spec.md, generate `<module>.feature` at the project's real feature-file location, generate the grounded page object/screen object/API client (plus locators, for frontend/mobile), generate step definitions, and — with --run — smoke-test and auto-un-disable the feature.
argument-hint: "<cucumberstudio-url> [--run]"
---

EXECUTE IMMEDIATELY.

This converts one CucumberStudio scenario into a grounded spec.md +
.feature file, the page object/screen object/API client (and locators,
for frontend/mobile), and step definitions underneath it. With --run, it
also smoke-tests the freshly-generated feature and removes the @disable
tag when it's genuinely ready.

## Parse the CucumberStudio URL

Expected pattern: `https://studio.cucumberstudio.com/projects/<projectId>/test-plan/folders/<folderId>/scenarios/<scenarioId>`

```bash
URL=$(echo "$ARGUMENTS" | awk '{print $1}')
RUN_FLAG=$(echo "$ARGUMENTS" | grep -qw -- "--run" && echo "true" || echo "false")
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

Write `$FEATURE_DIR/<MODULE>.feature` (using `$FEATURE_DIR` from "Discover
the test project's real conventions" above):

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
feature themselves even when `--run` wasn't used:

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

## Run smoke test (optional)

Skip this entire section when `RUN_FLAG=false` (the default) — most
CucumberStudio-fetched scenarios need a live device/browser this box may
not have. `RUN_COMMAND`/`RUN_COMMAND_<PLATFORM>` above was already
resolved regardless of `RUN_FLAG` — only the actual execution below is
gated. When `PLATFORMS_TO_RUN` is set (mobile cross-platform), this
section runs once per platform in `PLATFORMS_TO_RUN`, in order, for every
platform not skipped in "Prepare the smoke-run environment" above; when
it's unset, this section runs exactly once, exactly as before this
round.

### Retry — per step, not per run

Run the filtered command.

- **Pass** → proceed to "Auto-un-disable the feature".
- **Fail on a specific step**, and the failure is a locator/element-not-
  found error:
  - Re-groundable from a real source (re-read the real file if
    `SELECTOR_SOURCE=source` — it may have changed since the scan — or
    inspect a live app/browser via Appium/Playwright MCP if a live
    connection is available) → update that one `$LOCATOR_DIR` entry
    (merge, never overwrite the whole file), retry the SAME step. Up to 3
    heal attempts for that step specifically — a step that needed 2
    attempts doesn't reduce the budget for the step after it; each step
    gets its own fresh 3-attempt budget. 3 attempts on one step still
    failing → stop, print the runner output tail, leave it to the human.
  - Not re-groundable (no real source to check) → stop immediately (not
    counted against the 3-attempt budget — a hard stop, not a retry),
    print the runner output tail, leave it to the human. Never guess a
    replacement selector.
- **Fail for a non-locator reason** (timeout, environment, logic) → retry
  unchanged, counted against that step's 3-attempt budget.

Record for the Report: retry counts, which locator(s) were healed and
from what source, final pass/fail, and the failing step + output tail if
still failing.

## Auto-un-disable the feature

Read `$FEATURE_DIR/<MODULE>.feature`'s tag line (written in "Generate the
feature file").

- "Generate step definitions" left any TODO-stub binding → keep
  `@disable`, state which step(s) are stubbed and why in the Report.
- `RUN_FLAG=false` and no TODO-stub was left → remove `@disable` (no run
  evidence exists, but nothing is known to be missing either).
- `RUN_FLAG=true` and "Run smoke test" passed (with or without heals) →
  remove `@disable`.
- `RUN_FLAG=true` and "Run smoke test" is still failing after exhausting
  a step's 3-attempt budget, or hit a hard stop (no source to heal from)
  → keep `@disable`, state which step failed and why in the Report.

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
Smoke run: <not run | passed (n heal attempts: <list>) | failed after 3 attempts on step "<step text>": <tail output>>
Feature tag: <@disable removed | @disable kept — reason>

If a discovered convention was used: verify your existing runner config
actually picks up these new files (e.g. its feature-file glob) — this
command does not modify runner configuration.

Run it yourself:
  <RUN_COMMAND>
```

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
- Convention discovery (language, directory, locator file format, step-
  definition layout) uses best-effort matching from real existing files
  when found — this is the one place this command infers rather than
  asking. It does NOT apply to selector wording, real selectors, real
  endpoints, or business content, which are still never guessed.

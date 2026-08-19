---
name: scan-source
description: Scan one or more locally-cloned application source repositories (backend/frontend/mobile — auto-detected) and write grounded reference docs to .claude/docs/{backend,frontend,mobile}/, for writing autotests when no spec exists or the spec is outdated. Does not clone — pass an already-local path. Does not scan the autotest project itself — use /init existing for that.
argument-hint: "<path1> [path2] ..."
---

EXECUTE IMMEDIATELY.

This scans application source code the user has already cloned locally — it
never clones anything itself. It produces reference material (real API
endpoints, real UI test-ids, real business rules) for writing autotests when
there's no spec, or the spec is outdated. It does NOT scan the autotest
project itself — use `/init existing` for that.

## Parse arguments

`$ARGUMENTS` is one or more space-separated local paths. A path containing
spaces must be quoted by the user (e.g. `/scan-source "/path/with spaces/repo"`),
otherwise it will be misparsed as two separate paths.

If `$ARGUMENTS` is empty:
```bash
grep -n "^## .* — " .claude/CLAUDE.md 2>/dev/null
```
- No `.claude/CLAUDE.md`, or no `## <type> — <path>` lines found → stop
  with: `Usage: /scan-source <path1> [path2] ...`.
- One or more found → set the path list to every path extracted from those
  lines (everything after " — "). Print:
  ```
  No path given — rescanning <n> previously-scanned path(s):
    <type> — <path> (last scanned <date>)
    ...
  ```
  Then proceed with that list, exactly like a normal invocation below.

If `$ARGUMENTS` is non-empty, use the given path(s) as the list, unchanged.

Process each path in the order given — every section below runs once per
path, start to finish, before moving to the next path.

## Detect the source type

Before running the signal checks below, check whether this path was
already scanned: normalize it (resolve to an absolute path, strip any
trailing slash) and compare against every path recorded in
`.claude/CLAUDE.md`'s `# Scanned Sources` section (normalized the same
way).

```bash
cd "<path>" && pwd
grep -n "^## .* — " .claude/CLAUDE.md 2>/dev/null
```

A normalized match found → print `Rescanning <path> (last scanned
<date>)...`, unless `$ARGUMENTS` was empty and this path came from the
no-argument batch list — that case was already announced by "Parse
arguments," so skip the print here to avoid announcing the same rescan
twice; if the user explicitly supplied this exact path as an argument,
still print it even though it also matches. Either way, this message is
informational only — every signal check below still runs in full, since a
rescan's whole purpose is to catch changes (including a changed type or
platform). No match → proceed silently as a fresh scan (no message,
unchanged from before).

For the current path, check for these signals — collect **every** signal
found, not just the first match:

| Type | Signals |
|---|---|
| Mobile | `android/` + `ios/` directories at the path's root; `pubspec.yaml` (Flutter); `app.json` containing an `"expo"` key; a `package.json` dependency on `react-native`; any `*.xcodeproj`/`*.xcworkspace`; `AndroidManifest.xml`; `Info.plist` |
| Frontend | A `package.json` dependency on `react`, `vue`, `svelte`, `@angular/core`, `next`, or `nuxt`; an `index.html` at or near the root alongside a bundler config (`vite.config.*`, `webpack.config.*`); a `src/components/` or `src/pages/` directory |
| Backend | A `package.json` dependency on `express`, `fastify`, `@nestjs/core`, or `koa`; OR non-JS manifests: `requirements.txt`/`pyproject.toml` containing `flask`/`django`/`fastapi`; `go.mod`; `pom.xml`/`build.gradle` containing a Spring Boot dependency (and no `android { ... }` block); a `Gemfile` containing `rails`; a `controllers/`, `routes/`, or `migrations/` directory; a `Dockerfile` exposing a server port |

If the path doesn't exist or isn't readable, report it and skip to the next
path — do not attempt to fetch or clone it.

```bash
ls -la "<path>" 2>/dev/null || { echo "Path not found or unreadable: <path> — skipping"; }
cat "<path>/package.json" 2>/dev/null
cat "<path>/pubspec.yaml" 2>/dev/null
cat "<path>/app.json" 2>/dev/null
cat "<path>/requirements.txt" "<path>/pyproject.toml" 2>/dev/null
cat "<path>/pom.xml" "<path>/build.gradle" 2>/dev/null
cat "<path>/Gemfile" 2>/dev/null
cat "<path>/Dockerfile" 2>/dev/null
find "<path>" -maxdepth 2 \( -iname "AndroidManifest.xml" -o -iname "Info.plist" -o -iname "*.xcodeproj" -o -iname "*.xcworkspace" -o -iname "requirements.txt" -o -iname "pyproject.toml" -o -iname "go.mod" -o -iname "pom.xml" -o -iname "build.gradle" -o -iname "Gemfile" -o -iname "Dockerfile" -o -iname "app.json" \) 2>/dev/null
find "<path>" -maxdepth 2 -type d \( -iname "controllers" -o -iname "routes" -o -iname "migrations" -o -iname "components" -o -iname "pages" -o -iname "android" -o -iname "ios" \) 2>/dev/null
find "<path>" -maxdepth 2 -iname "index.html" 2>/dev/null
find "<path>" -maxdepth 2 \( -iname "vite.config.*" -o -iname "webpack.config.*" \) 2>/dev/null
```

### Confirm the detected type

**Exactly one type matched:**
```
Path: <path>
Detected: <type> (based on: <specific signals found — list them>)

Correct? (y / n — choose a different type)
```
Wait for the reply. `y` → proceed with `<type>`. `n` → ask "Which type is
it: backend / frontend / mobile?", wait for the reply, use that instead.

**More than one type matched (monorepo):**
```
Path: <path>
Multiple signals found:
  - <type A>: <signals>
  - <type B>: <signals>

This looks like a monorepo. Options:
  1  Scan as <type A> only
  2  Scan as <type B> only
  3  Give me narrower sub-paths to scan separately (e.g. <path>/api, <path>/web)

Reply: 1 / 2 / 3
```
Wait for the reply. `1`/`2` → proceed with the chosen type on this path.
`3` → ask for the sub-paths, then restart "Detect the source type" for each
sub-path given, as if they were separate entries in the original path list.

**No type matched:**
```
Path: <path>
No backend/frontend/mobile signal found.

Which type is it: backend / frontend / mobile?
```
Wait for the reply — never guess. Use the given type.

## Check for existing content (per confirmed type)

```bash
ls -la .claude/docs/<type>/ 2>/dev/null
```

- Empty/missing → proceed to scan.
- Has content → ask:
  ```
  .claude/docs/<type>/ already has content (from a previous scan).

    1  Overwrite — replace all files for this type
    2  Merge — only create files that are missing
    3  Skip this path

  Reply: 1 / 2 / 3
  ```
  Wait for the reply. `3` → skip this path entirely, note it in the final
  report, move to the next path. `1`/`2` → proceed, honoring the choice
  when writing files below.

## Scan and write — backend

Read enough of the path to answer, for each item below, either a grounded
fact or "not determined". Do not guess.

```bash
cat "<path>/package.json" 2>/dev/null
cat "<path>/requirements.txt" "<path>/pyproject.toml" "<path>/go.mod" "<path>/pom.xml" "<path>/build.gradle" "<path>/Gemfile" 2>/dev/null
ls -la "<path>"
find "<path>" -maxdepth 3 -type d \( -iname "controllers" -o -iname "routes" -o -iname "services" -o -iname "models" -o -iname "migrations" \) 2>/dev/null
```
Read 2-3 representative files from any `controllers/`/`routes/` directory
found, to ground real endpoints and business rules.

Write (respecting the overwrite/merge/skip choice above):

**`.claude/docs/backend/architecture.md`** — layers present (controller/
service/repository/etc. — only ones that actually exist), key libraries/
frameworks found in the manifest, database technology if evidenced
(connection string pattern, ORM dependency, migration folder). "not
determined" for anything not evidenced.

**`.claude/docs/backend/api-contracts.md`** — real endpoints found in route/
controller code: HTTP method, path, request/response shape as written in
the code. One entry per endpoint found. "not determined — no route/
controller code found" if none.

**`.claude/docs/backend/business-logic.md`** — domain rules/validations
found in real code (e.g. a validation constant, a business rule check, a
computed-field formula) — quote the actual code. "not determined — no
business logic evidenced" if none found.

## Scan and write — frontend

Read enough of the path to answer, for each item below, either a grounded
fact or "not determined". Do not guess.

```bash
cat "<path>/package.json" 2>/dev/null
ls -la "<path>"
find "<path>" -maxdepth 3 -type d \( -iname "components" -o -iname "pages" -o -iname "routes" \) 2>/dev/null
find "<path>" -maxdepth 2 -iname "*.router.*" -o -iname "routes.*" -o -iname "App.tsx" -o -iname "App.jsx" 2>/dev/null
```
Read 2-3 representative files from any `components/`/`pages/` directory
found, and any routing config, to ground real components and routes.

After reading `package.json`, detect the specific framework and set `WEB_FRAMEWORK`:

```bash
cat "<path>/package.json" 2>/dev/null | grep -E '"next"|"react"|"vue"|"nuxt"|"@angular/core"|"svelte"'
ls "<path>/next.config."* "<path>/nuxt.config."* "<path>/angular.json" "<path>/svelte.config."* 2>/dev/null
```

Map signals to `WEB_FRAMEWORK` using this priority (first match wins):

| Signal | `WEB_FRAMEWORK` |
|---|---|
| `next` dependency or `next.config.*` | `Next.js` |
| `nuxt` dependency or `nuxt.config.*` | `Nuxt` |
| `vue` dependency (no nuxt) | `Vue` |
| `@angular/core` or `angular.json` | `Angular` |
| `svelte` or `svelte.config.*` | `Svelte` |
| `react` dependency (no next) | `React` |
| None of the above | `not determined` |

For Next.js, additionally detect router type:
```bash
ls "<path>/app/" "<path>/src/app/" 2>/dev/null
ls "<path>/pages/" "<path>/src/pages/" 2>/dev/null
```
If `app/` or `src/app/` exists → append `(App Router)` to `WEB_FRAMEWORK`. If only `pages/` or `src/pages/` → append `(Pages Router)`.

Write (respecting the overwrite/merge/skip choice from "Check for existing
content"):

**`.claude/docs/frontend/architecture.md`** — starts with `**Framework:**
<WEB_FRAMEWORK>` on its own line (modelled on mobile's `**Platform:**`
line), then: component layers, state-management library (if a dependency
like `redux`/`zustand`/`pinia`/`vuex` is evidenced), routing library, key
build tooling (bundler config found). "not determined" for anything not
evidenced.

**`.claude/docs/frontend/components.md`** — key components found, with
their real selector attributes as they appear in the code. When an element
has more than one identifying attribute, record it under the highest-priority
type found, in this order: **1. `data-test`/`data-testid`** → **2. `id`**
→ **3. CSS selector/class** → **4. XPath** (last resort — only when nothing
higher in the list exists). Note which tier was used for each entry. One
entry per component read. Also record the real file path each entry was
read from (relative to `<path>`), as a `**File:**` line directly under the
component's heading — this lets `/do-cucumber-task` jump straight to the
real file later without re-searching:
```markdown
### LoginForm
**File:** src/components/LoginForm.tsx
- data-testid="login-submit" → submit button
```
"not determined — no components found" if none.

Before writing `locators.md`, detect the project's primary locator strategy by counting hits across `src/` (or the project root if no `src/` directory):

```bash
SRC_DIR=$([ -d "<path>/src" ] && echo "<path>/src" || echo "<path>")
TESTID_COUNT=$(grep -rE 'data-testid=|data-test=' "$SRC_DIR" --include='*.tsx' --include='*.jsx' --include='*.vue' --include='*.html' --exclude-dir=node_modules --exclude-dir=dist --exclude-dir=.next --exclude-dir=build 2>/dev/null | wc -l)
ARIA_COUNT=$(grep -rE 'aria-label=|role=' "$SRC_DIR" --include='*.tsx' --include='*.jsx' --include='*.vue' --include='*.html' --exclude-dir=node_modules --exclude-dir=dist --exclude-dir=.next --exclude-dir=build 2>/dev/null | wc -l)
ID_COUNT=$(grep -rE 'id="[^"]*"' "$SRC_DIR" --include='*.tsx' --include='*.jsx' --include='*.vue' --include='*.html' --exclude-dir=node_modules --exclude-dir=dist --exclude-dir=.next --exclude-dir=build 2>/dev/null | wc -l)
echo "TESTID=$TESTID_COUNT ARIA=$ARIA_COUNT ID=$ID_COUNT"
```

Rank strategies by hit count. The highest count becomes `PRIMARY_STRATEGY`. If all are 0, set `PRIMARY_STRATEGY=none` and use the default Playwright priority order.

```bash
# data-testid / data-test
grep -rn 'data-testid="[^"]*"\|data-test="[^"]*"' "$SRC_DIR" --include='*.tsx' --include='*.jsx' --include='*.vue' --include='*.html' --exclude-dir=node_modules --exclude-dir=dist --exclude-dir=.next --exclude-dir=build 2>/dev/null | head -30

# aria-label / role
grep -rn 'aria-label="[^"]*"\|role="[^"]*"' "$SRC_DIR" --include='*.tsx' --include='*.jsx' --include='*.vue' --include='*.html' --exclude-dir=node_modules --exclude-dir=dist --exclude-dir=.next --exclude-dir=build 2>/dev/null | head -30

# id attributes
grep -rn 'id="[^"]*"' "$SRC_DIR" --include='*.tsx' --include='*.jsx' --include='*.vue' --include='*.html' --exclude-dir=node_modules --exclude-dir=dist --exclude-dir=.next --exclude-dir=build 2>/dev/null | head -30

# CSS class (last resort — only if higher strategies have 0 hits)
grep -rn 'className="[^"]*"' "$SRC_DIR" --include='*.tsx' --include='*.jsx' --include='*.vue' --exclude-dir=node_modules --exclude-dir=dist --exclude-dir=.next --exclude-dir=build 2>/dev/null | head -20
```

Read 2-3 representative files found by the above to ground real values (not just file paths).

**`.claude/docs/frontend/locators.md`** — a flat catalog of test-automation
hooks found in the real source, grouped by strategy — not by component (that
is `components.md`'s job). Write with this structure:

```markdown
# Frontend Locators

**Primary strategy:** <PRIMARY_STRATEGY> (<N> hits — highest among scanned attributes)
**Playwright priority order:** getByRole → getByLabel → getByTestId → getByText → CSS

## data-testid (primary / secondary / tertiary — based on hit rank)
- `<value>` → <element description> — <relative/file/path>:<line>

## aria-label / role (<rank>)
- `aria-label="<value>"` → <element description> — <relative/file/path>:<line>

## id (<rank>)
- `id="<value>"` → <element description> — <relative/file/path>:<line>

## CSS selector (last resort)
- `.<class>` → <element description> — <relative/file/path>:<line>
```

Omit any section for which no hits were found. If `PRIMARY_STRATEGY=none`
(no hits for any strategy), write "not determined — no locator hooks found
in source" instead of the sections above. Each entry records the real file
path and line number as the source of truth.

**`.claude/docs/frontend/routes.md`** — real page routes/URL patterns and
the navigation flow between them, as evidenced by the routing config/code.
"not determined — no routing code found" if none.

## Scan and write — mobile

### Determine Android vs. iOS

```bash
ls -la "<path>/android" 2>/dev/null
find "<path>" -maxdepth 2 \( -iname "AndroidManifest.xml" -o -iname "build.gradle*" \) 2>/dev/null
ls -la "<path>/ios" 2>/dev/null
find "<path>" -maxdepth 2 \( -iname "Info.plist" -o -iname "*.xcodeproj" -o -iname "*.xcworkspace" -o -iname "Podfile" \) 2>/dev/null
```
- Android signals found AND iOS signals found → `MOBILE_PLATFORM=Android + iOS`.
- Only Android signals → `MOBILE_PLATFORM=Android`.
- Only iOS signals → `MOBILE_PLATFORM=iOS`.
- Neither found (e.g. an Expo managed-workflow project with only
  `app.json`) → `MOBILE_PLATFORM=not determined — no native android/ios
  folders found (Expo managed workflow?)`.

Read enough of the path to answer, for each item below, either a grounded
fact or "not determined". Do not guess.

```bash
cat "<path>/package.json" 2>/dev/null
cat "<path>/pubspec.yaml" 2>/dev/null
ls -la "<path>"
find "<path>" -maxdepth 3 -iname "*Screen*" -o -iname "*navigator*" -o -iname "*navigation*" 2>/dev/null
```
Read 2-3 representative screen/navigation files found, to ground real
screens and navigation flow.

Write (respecting the overwrite/merge/skip choice from "Check for existing
content"):

**`.claude/docs/mobile/architecture.md`** — starts with `**Platform**:
<MOBILE_PLATFORM>` on its own line, then: screen layer, navigation
library (e.g. `react-navigation`, a native `Navigator`/`NavHost` pattern if
evidenced), state-management approach. "not determined" for anything not
evidenced.

**`.claude/docs/mobile/screens.md`** — real screens found, with their
selector attributes as they appear in the code. When an element has more
than one identifying attribute, record it under the highest-priority type
found, in this order: **1. `data-test`/`data-testid`/`testID`/accessibility
id** → **2. `id`/resource-id** → **3. CSS selector-equivalent/class** →
**4. XPath** (last resort — only when nothing higher in the list exists).
Note which tier was used for each entry. One entry per screen read. Also
record the real file path each entry was read from (relative to `<path>`),
as a `**File:**` line directly under the screen's heading — this lets
`/do-cucumber-task` jump straight to the real file later without
re-searching:
```markdown
### LoginScreen
**File:** android/app/src/main/java/com/example/LoginScreen.kt
- testTag("login_button") → login button
```
"not determined — no screens found" if none.

**`.claude/docs/mobile/navigation.md`** — the navigation graph/flow between
screens, as evidenced by the routing/navigation code. "not determined — no
navigation code found" if none.

**`.claude/docs/mobile/locators.md`** — a flat catalog of test-automation
hooks by strategy (not by screen — this complements `screens.md`, it does
not repeat it). All greps below exclude common noise dirs (`node_modules`,
`.git`, `build`, `Pods`, `DerivedData`, `.gradle`) via `--exclude-dir`,
since scanning dependency/build trees is slow and produces false hits from
third-party code.

Only run the Android block when `MOBILE_PLATFORM` includes Android:
```bash
grep -rlE "Modifier\.testTag\(|\.semantics\s*\{|createComposeRule\(\)|ComposeTestRule" "<path>" --include='*.kt' --exclude-dir=build --exclude-dir=.gradle --exclude-dir=node_modules 2>/dev/null
grep -rlE 'contentDescription\s*=|android:contentDescription="|resource-id' "<path>" --include='*.kt' --include='*.xml' --exclude-dir=build --exclude-dir=.gradle --exclude-dir=node_modules 2>/dev/null
grep -rlE 'AppiumDriver|MobileElement|@AndroidFindBy|UiSelector' "<path>" --exclude-dir=build --exclude-dir=.gradle --exclude-dir=node_modules 2>/dev/null
```

Only run the iOS block when `MOBILE_PLATFORM` includes iOS:
```bash
grep -rlE '\.accessibilityIdentifier\(|accessibilityIdentifier\s*=|@iOSXCUITFindBy' "<path>" --include='*.swift' --exclude-dir=Pods --exclude-dir=DerivedData --exclude-dir=node_modules 2>/dev/null
grep -rlE 'app\.(buttons|staticTexts|textFields|cells|otherElements)\[' "<path>" --exclude-dir=Pods --exclude-dir=DerivedData --exclude-dir=node_modules 2>/dev/null
```

Read 2-3 representative files found by the above, to ground real locator
values — not just "a testTag exists somewhere."

Write `.claude/docs/mobile/locators.md` with one top-level section per
platform found (both, when `MOBILE_PLATFORM=Android + iOS`):

```markdown
## Android
### Appium locators
<real accessibility id / resource-id / content-desc values found, or
"not determined — none found">
### Compose Testing
<real testTag / semantics values found, or "not determined — none found">

## iOS
### Accessibility identifiers / XCUITest queries
<real values found, or "not determined — none found">
```
Omit the `## Android` or `## iOS` top-level section entirely when
`MOBILE_PLATFORM` doesn't include that platform (don't write an empty
section for a platform that isn't present).

**`.claude/docs/mobile/directory-tree.md`** — the real scanned directory
structure, depth-limited and excluding the same noise dirs as above.

```bash
find "<path>" -maxdepth 4 \
  -not -path '*/node_modules/*' -not -path '*/.git/*' \
  -not -path '*/build/*' -not -path '*/Pods/*' \
  -not -path '*/DerivedData/*' -not -path '*/.gradle/*' \
  | sort
```
Write the raw output as a fenced code block, with a one-line header noting
the scanned path and the depth limit used (`maxdepth 4`).

## Update the cumulative index

Read `.claude/CLAUDE.md` if it exists. If it has a `# Scanned Sources`
section with an entry for this exact `<path>`, update that entry in place
(new timestamp, new summary). Otherwise append a new entry. Never remove
other entries.

```markdown
# Scanned Sources

## <type> — <path>
**Last scanned:** <ISO timestamp>
<1-2 line summary of what was found>
See: .claude/docs/<type>/
```
For `mobile` entries specifically, insert one additional line right after
`**Last scanned:**`:
```
**Platform:** <MOBILE_PLATFORM>
```

For `frontend` entries specifically, insert one additional line right after
`**Last scanned:**`:
```
**Framework:** <WEB_FRAMEWORK>
```

This full template — including the `# Scanned Sources` heading — is only
for the create case, below. If `.claude/CLAUDE.md` already exists, append
(or update in place) only the `## <type> — <path>` entry block; never
repeat the `# Scanned Sources` H1, which must appear exactly once in the
file.

If `.claude/CLAUDE.md` doesn't exist yet, create it with just the
`# Scanned Sources` heading and this path's entry.

## Report

After all given paths are processed, list every subfolder written (or
skipped), each with a 1-2 line summary of its actual content — not a
generic description. For every `mobile` path, state `MOBILE_PLATFORM`
explicitly and confirm `locators.md` and `directory-tree.md` are included
in the file list (written, or "⊘ Skipped <file> (already exists)" per the
overwrite/merge/skip choice).
For every `frontend` path, state `WEB_FRAMEWORK` explicitly and confirm
`locators.md` and `directory-tree.md` are included in the file list
(written, or "⊘ Skipped <file> (already exists)" per the overwrite/merge/
skip choice).

## Rules

- Do NOT clone anything — only read paths that already exist locally.
- Do NOT scan the autotest/test-tooling project itself — use
  `/init existing` for that.
- Do NOT run any tests, invoke a test-generation pipeline, or generate
  feature files/page objects/step definitions/spec.md — this command
  produces reference material only.
- Do NOT run `git` commands — this command only reads files.
- Never guess a source type or invent content — ask when ambiguous, write
  "not determined" when evidence is absent.

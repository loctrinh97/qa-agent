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

`$ARGUMENTS` is one or more space-separated local paths. If none given, stop
with: `Usage: /scan-source <path1> [path2] ...`. A path containing spaces
must be quoted by the user (e.g. `/scan-source "/path/with spaces/repo"`),
otherwise it will be misparsed as two separate paths.

Process each path in the order given — every section below runs once per
path, start to finish, before moving to the next path.

## Detect the source type

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

    1  Overwrite — replace all 3 files
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

Write (respecting the overwrite/merge/skip choice from "Check for existing
content"):

**`.claude/docs/frontend/architecture.md`** — component layers, state-
management library (if a dependency like `redux`/`zustand`/`pinia`/
`vuex` is evidenced), routing library, key build tooling (bundler config
found). "not determined" for anything not evidenced.

**`.claude/docs/frontend/components.md`** — key components found, with
their real selector attributes as they appear in the code. When an element
has more than one identifying attribute, record it under the highest-priority
type found, in this order: **1. `data-test`/`data-testid`** → **2. `id`**
→ **3. CSS selector/class** → **4. XPath** (last resort — only when nothing
higher in the list exists). Note which tier was used for each entry. One
entry per component read. "not determined — no components found" if none.

**`.claude/docs/frontend/routes.md`** — real page routes/URL patterns and
the navigation flow between them, as evidenced by the routing config/code.
"not determined — no routing code found" if none.

## Scan and write — mobile

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

**`.claude/docs/mobile/architecture.md`** — screen layer, navigation
library (e.g. `react-navigation`, a native `Navigator`/`NavHost` pattern if
evidenced), state-management approach. "not determined" for anything not
evidenced.

**`.claude/docs/mobile/screens.md`** — real screens found, with their
selector attributes as they appear in the code. When an element has more
than one identifying attribute, record it under the highest-priority type
found, in this order: **1. `data-test`/`data-testid`/`testID`/accessibility
id** → **2. `id`/resource-id** → **3. CSS selector-equivalent/class** →
**4. XPath** (last resort — only when nothing higher in the list exists).
Note which tier was used for each entry. One entry per screen read. "not
determined — no screens found" if none.

**`.claude/docs/mobile/navigation.md`** — the navigation graph/flow between
screens, as evidenced by the routing/navigation code. "not determined — no
navigation code found" if none.

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
generic description.

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

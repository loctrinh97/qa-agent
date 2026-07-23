# `/scan-source` Command Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add `commands/scan-source.md` to `lian-qa-plugin` — scans one or more locally-cloned application source repos (backend/frontend/mobile, auto-detected), writes grounded reference docs to `.claude/docs/{backend,frontend,mobile}/`, and maintains a cumulative `.claude/CLAUDE.md` index.

**Architecture:** A single prose-driven command file, same pattern as `commands/init.md` and `commands/spec.md` — no companion script, because reading and classifying arbitrary source code requires LLM judgment. Like `/spec`, this is mostly a linear flow (parse → detect → confirm → scan → write → index → report) with a per-type loop; each task in this plan appends the next section to the end of the growing file.

**Tech Stack:** Markdown prompt command (Claude Code plugin convention). Uses only `Read`/`Grep`/`Glob`/`Bash` (`ls`, `find`, `cat`) — no cloning, no MCP, no new dependencies.

## Global Constraints

- Reference design: `docs/superpowers/specs/2026-07-23-scan-source-command-design.md`.
- **This command never clones anything.** It only reads paths that already exist locally. If a given path doesn't exist, report it and skip — never attempt to fetch/clone it.
- **This command never scans the autotest/test-tooling project itself** — that stays `/init existing`'s job. Do not add an `autotest/` category anywhere.
- Output tree: `.claude/docs/{backend,frontend,mobile}/` — only the subfolders for types actually scanned. 3 files per type (see per-type content in each task).
- Detection is per-path and must never silently guess: exactly one signal match → confirm with the user; multiple matches → ask the user to pick one or split into sub-paths; zero matches → ask the user directly what type it is. Every "ask" step must wait for the reply before continuing.
- Repeat-run behavior is additive: a run only touches the subfolder(s) for the path(s) given that run. Re-scanning into an already-populated subfolder asks overwrite / merge / skip, scoped to that one subfolder.
- `.claude/CLAUDE.md`'s `# Scanned Sources` index is cumulative — new entries are appended (or the matching entry updated in place if the same source path is re-scanned); other entries are never removed.
- Every content claim in a generated doc must trace to real code found in the scanned path. Write the literal string "not determined" for anything not evidenced — never invent example endpoints, components, or business rules.
- No automated git commands anywhere in the command — this command only reads files and writes into `.claude/`.
- Command frontmatter: `name: scan-source`, `argument-hint: "<path1> [path2] ..."`.

---

## Task 1: Command skeleton + argument parsing + detection heuristics

**Files:**
- Create: `commands/scan-source.md`

**Interfaces:**
- Produces: the file's frontmatter and its first two sections ("Parse arguments", "Detect the source type" with the confirmation sub-flows). Task 2 appends "Check for existing content" + the backend scan/write section immediately after this task's content; Tasks 3-5 append after that, in file order.

- [ ] **Step 1: Write the command skeleton**

Create `commands/scan-source.md` with exactly this content:

```markdown
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
with: `Usage: /scan-source <path1> [path2] ...`

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
find "<path>" -maxdepth 2 \( -iname "AndroidManifest.xml" -o -iname "Info.plist" -o -iname "*.xcodeproj" -o -iname "*.xcworkspace" -o -iname "requirements.txt" -o -iname "pyproject.toml" -o -iname "go.mod" -o -iname "pom.xml" -o -iname "build.gradle" -o -iname "Gemfile" -o -iname "Dockerfile" -o -iname "app.json" \) 2>/dev/null
find "<path>" -maxdepth 2 -type d \( -iname "controllers" -o -iname "routes" -o -iname "migrations" -o -iname "components" -o -iname "pages" -o -iname "android" -o -iname "ios" \) 2>/dev/null
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
```

- [ ] **Step 2: Verify the file was created correctly**

```bash
cd /Users/lian.trinh/SourceCode/setup-qa-plugin/lian-qa-plugin
awk '/^---$/{c++} c==1' commands/scan-source.md | grep -E '^(name|description|argument-hint):'
grep -n "^## Parse arguments\|^## Detect the source type\|^### Confirm the detected type" commands/scan-source.md
```
Expected: the 3 frontmatter lines, then 3 heading lines in order.

- [ ] **Step 3: Verify the detection heuristics against 3 synthetic fixtures**

```bash
SCRATCH=/private/tmp/scan-source-detect-check
rm -rf "$SCRATCH" && mkdir -p "$SCRATCH/backend-fixture/controllers" "$SCRATCH/frontend-fixture/src/components" "$SCRATCH/mobile-fixture/android" "$SCRATCH/mobile-fixture/ios"

# Backend fixture: express + controllers/
cat > "$SCRATCH/backend-fixture/package.json" <<'EOF'
{ "name": "backend-fixture", "dependencies": { "express": "^4.18.0" } }
EOF
cat > "$SCRATCH/backend-fixture/controllers/userController.js" <<'EOF'
router.get('/api/users', (req, res) => { res.json({ users: [] }); });
EOF

# Frontend fixture: react + index.html + vite config + src/components
cat > "$SCRATCH/frontend-fixture/package.json" <<'EOF'
{ "name": "frontend-fixture", "dependencies": { "react": "^18.2.0" } }
EOF
touch "$SCRATCH/frontend-fixture/index.html" "$SCRATCH/frontend-fixture/vite.config.js"
cat > "$SCRATCH/frontend-fixture/src/components/LoginForm.jsx" <<'EOF'
export const LoginForm = () => <button data-testid="login-button">Log in</button>;
EOF

# Mobile fixture: android/ + ios/ dirs
touch "$SCRATCH/mobile-fixture/android/.gitkeep" "$SCRATCH/mobile-fixture/ios/.gitkeep"

for f in backend-fixture frontend-fixture mobile-fixture; do
  echo "=== $f ==="
  cat "$SCRATCH/$f/package.json" 2>/dev/null
  find "$SCRATCH/$f" -maxdepth 2 -type d \( -iname "controllers" -o -iname "routes" -o -iname "migrations" -o -iname "components" -o -iname "pages" -o -iname "android" -o -iname "ios" \)
done
rm -rf "$SCRATCH"
```

Expected: `backend-fixture` shows `express` in its `package.json` and a
`controllers` directory match (→ Backend signals). `frontend-fixture` shows
`react` in its `package.json` and a `components` directory match (→ Frontend
signals). `mobile-fixture` shows `android` and `ios` directory matches (→
Mobile signals). Manually confirm against the Detect-the-source-type table
that each fixture's signals map to exactly the intended type with no
cross-match.

- [ ] **Step 4: Commit**

```bash
cd /Users/lian.trinh/SourceCode/setup-qa-plugin/lian-qa-plugin
git add commands/scan-source.md
git commit -m "Add /scan-source command skeleton with argument parsing and detection heuristics"
```

---

## Task 2: Per-subfolder existing-check + backend scan/write

**Files:**
- Modify: `commands/scan-source.md` (append after Task 1's content)
- Test: a scratch directory with a synthetic backend fixture (not committed).

**Interfaces:**
- Consumes: the confirmed `<type>` and `<path>` from Task 1's detection flow.
- Produces: `.claude/docs/backend/{architecture,api-contracts,business-logic}.md`
  when `<type>` is `backend` — the pattern Tasks 3-4 mirror for frontend/mobile.

- [ ] **Step 1: Append the existing-check + backend sections**

Append to the end of `commands/scan-source.md`:

```markdown

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
```

- [ ] **Step 2: Verify the sections landed correctly**

```bash
cd /Users/lian.trinh/SourceCode/setup-qa-plugin/lian-qa-plugin
grep -n "^## Check for existing content\|^## Scan and write — backend" commands/scan-source.md
```
Expected: 2 lines, in order.

- [ ] **Step 3: Live smoke test — scan a real backend fixture**

```bash
SCRATCH=/private/tmp/scan-source-backend-smoke
rm -rf "$SCRATCH" && mkdir -p "$SCRATCH/repo/controllers" "$SCRATCH/workspace"
cat > "$SCRATCH/repo/package.json" <<'EOF'
{
  "name": "checkout-service",
  "dependencies": { "express": "^4.18.0", "pg": "^8.11.0" }
}
EOF
cat > "$SCRATCH/repo/controllers/orderController.js" <<'EOF'
const router = require('express').Router();

// Minimum order amount is $10 — orders below this are rejected.
const MIN_ORDER_AMOUNT = 10;

router.post('/api/orders', (req, res) => {
  if (req.body.amount < MIN_ORDER_AMOUNT) {
    return res.status(400).json({ error: 'Order amount too low' });
  }
  res.status(201).json({ orderId: 'ord_123', status: 'created' });
});

router.get('/api/orders/:id', (req, res) => {
  res.json({ orderId: req.params.id, status: 'created' });
});

module.exports = router;
EOF
cd "$SCRATCH/workspace"
```

Follow the command's "Check for existing content" (empty, proceed) and
"Scan and write — backend" sections manually against `$SCRATCH/repo`: read
the real `package.json` and `controllers/orderController.js`, then use the
Write tool to create `.claude/docs/backend/architecture.md`,
`.claude/docs/backend/api-contracts.md`, and
`.claude/docs/backend/business-logic.md` in `$SCRATCH/workspace` with real,
grounded content — `api-contracts.md` should list the real `POST /api/orders`
and `GET /api/orders/:id` endpoints; `business-logic.md` should quote the
real `MIN_ORDER_AMOUNT = 10` rule.

```bash
cat "$SCRATCH/workspace/.claude/docs/backend/api-contracts.md"
cat "$SCRATCH/workspace/.claude/docs/backend/business-logic.md"
rm -rf "$SCRATCH"
```
Expected: both files contain the real endpoint paths and the real `10`
minimum-order-amount rule — not invented examples.

- [ ] **Step 4: Commit**

```bash
cd /Users/lian.trinh/SourceCode/setup-qa-plugin/lian-qa-plugin
git add commands/scan-source.md
git commit -m "Add /scan-source per-subfolder existing-check and backend scan/write"
```

---

## Task 3: Frontend scan/write

**Files:**
- Modify: `commands/scan-source.md` (append after Task 2's content)
- Test: a scratch directory with a synthetic frontend fixture.

**Interfaces:**
- Consumes: the confirmed `<type>` (`frontend`) and `<path>`.
- Produces: `.claude/docs/frontend/{architecture,components,routes}.md`.

- [ ] **Step 1: Append the frontend section**

Append to the end of `commands/scan-source.md`:

```markdown

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
their real `data-testid`/selector attributes as they appear in the code.
One entry per component read. "not determined — no components found" if
none.

**`.claude/docs/frontend/routes.md`** — real page routes/URL patterns and
the navigation flow between them, as evidenced by the routing config/code.
"not determined — no routing code found" if none.
```

- [ ] **Step 2: Verify the section landed correctly**

```bash
cd /Users/lian.trinh/SourceCode/setup-qa-plugin/lian-qa-plugin
grep -n "^## Scan and write — frontend" commands/scan-source.md
```
Expected: 1 line.

- [ ] **Step 3: Live smoke test — scan a real frontend fixture**

```bash
SCRATCH=/private/tmp/scan-source-frontend-smoke
rm -rf "$SCRATCH" && mkdir -p "$SCRATCH/repo/src/components" "$SCRATCH/workspace"
cat > "$SCRATCH/repo/package.json" <<'EOF'
{
  "name": "checkout-web",
  "dependencies": { "react": "^18.2.0", "react-router-dom": "^6.20.0" }
}
EOF
touch "$SCRATCH/repo/index.html" "$SCRATCH/repo/vite.config.js"
cat > "$SCRATCH/repo/src/components/CheckoutButton.jsx" <<'EOF'
export const CheckoutButton = ({ onClick }) => (
  <button data-testid="checkout-submit-button" onClick={onClick}>
    Place Order
  </button>
);
EOF
cat > "$SCRATCH/repo/src/App.jsx" <<'EOF'
import { Routes, Route } from 'react-router-dom';
export const App = () => (
  <Routes>
    <Route path="/checkout" element={<CheckoutPage />} />
    <Route path="/checkout/confirm" element={<ConfirmPage />} />
  </Routes>
);
EOF
cd "$SCRATCH/workspace"
```

Follow the command's "Scan and write — frontend" section manually against
`$SCRATCH/repo`: read the real `package.json`, `CheckoutButton.jsx`, and
`App.jsx`, then write `.claude/docs/frontend/architecture.md`,
`.claude/docs/frontend/components.md`, and `.claude/docs/frontend/routes.md`
in `$SCRATCH/workspace` — `components.md` should quote the real
`data-testid="checkout-submit-button"`; `routes.md` should list the real
`/checkout` and `/checkout/confirm` routes.

```bash
cat "$SCRATCH/workspace/.claude/docs/frontend/components.md"
cat "$SCRATCH/workspace/.claude/docs/frontend/routes.md"
rm -rf "$SCRATCH"
```
Expected: both files contain the real test-id and the real routes — not
invented examples.

- [ ] **Step 4: Commit**

```bash
cd /Users/lian.trinh/SourceCode/setup-qa-plugin/lian-qa-plugin
git add commands/scan-source.md
git commit -m "Add /scan-source frontend scan/write"
```

---

## Task 4: Mobile scan/write

**Files:**
- Modify: `commands/scan-source.md` (append after Task 3's content)
- Test: a scratch directory with a synthetic mobile fixture.

**Interfaces:**
- Consumes: the confirmed `<type>` (`mobile`) and `<path>`.
- Produces: `.claude/docs/mobile/{architecture,screens,navigation}.md`.

- [ ] **Step 1: Append the mobile section**

Append to the end of `commands/scan-source.md`:

```markdown

## Scan and write — mobile

Read enough of the path to answer, for each item below, either a grounded
fact or "not determined". Do not guess.

```bash
cat "<path>/package.json" 2>/dev/null
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
accessibility-id/testID attributes as they appear in the code. One entry
per screen read. "not determined — no screens found" if none.

**`.claude/docs/mobile/navigation.md`** — the navigation graph/flow between
screens, as evidenced by the routing/navigation code. "not determined — no
navigation code found" if none.
```

- [ ] **Step 2: Verify the section landed correctly**

```bash
cd /Users/lian.trinh/SourceCode/setup-qa-plugin/lian-qa-plugin
grep -n "^## Scan and write — mobile" commands/scan-source.md
```
Expected: 1 line.

- [ ] **Step 3: Live smoke test — scan a real mobile fixture**

```bash
SCRATCH=/private/tmp/scan-source-mobile-smoke
rm -rf "$SCRATCH" && mkdir -p "$SCRATCH/repo/android" "$SCRATCH/repo/ios" "$SCRATCH/repo/src/screens" "$SCRATCH/workspace"
cat > "$SCRATCH/repo/package.json" <<'EOF'
{
  "name": "checkout-mobile",
  "dependencies": { "react-native": "^0.72.0", "@react-navigation/native": "^6.1.0" }
}
EOF
cat > "$SCRATCH/repo/src/screens/CheckoutScreen.tsx" <<'EOF'
export const CheckoutScreen = () => (
  <Button testID="checkout-submit-button" title="Place Order" onPress={onSubmit} />
);
EOF
cat > "$SCRATCH/repo/src/navigation/AppNavigator.tsx" <<'EOF'
<Stack.Navigator>
  <Stack.Screen name="Checkout" component={CheckoutScreen} />
  <Stack.Screen name="OrderConfirm" component={OrderConfirmScreen} />
</Stack.Navigator>
EOF
cd "$SCRATCH/workspace"
```

Follow the command's "Scan and write — mobile" section manually against
`$SCRATCH/repo`: read the real `package.json`, `CheckoutScreen.tsx`, and
`AppNavigator.tsx`, then write `.claude/docs/mobile/architecture.md`,
`.claude/docs/mobile/screens.md`, and `.claude/docs/mobile/navigation.md` in
`$SCRATCH/workspace` — `screens.md` should quote the real
`testID="checkout-submit-button"`; `navigation.md` should list the real
`Checkout` → `OrderConfirm` navigation flow.

```bash
cat "$SCRATCH/workspace/.claude/docs/mobile/screens.md"
cat "$SCRATCH/workspace/.claude/docs/mobile/navigation.md"
rm -rf "$SCRATCH"
```
Expected: both files contain the real testID and the real screen flow —
not invented examples.

- [ ] **Step 4: Commit**

```bash
cd /Users/lian.trinh/SourceCode/setup-qa-plugin/lian-qa-plugin
git add commands/scan-source.md
git commit -m "Add /scan-source mobile scan/write"
```

---

## Task 5: Cumulative CLAUDE.md index + final report + Rules

**Files:**
- Modify: `commands/scan-source.md` (append after Task 4's content — this is
  the last section, completing the file)
- Test: a scratch directory reusing the Task 2 backend fixture and Task 3
  frontend fixture, to prove the additive/cumulative behavior across two
  separate scans into the same `.claude/` tree.

**Interfaces:**
- Consumes: the type/path/summary from every path processed.
- Produces: the complete command file.

- [ ] **Step 1: Append the index + report + Rules sections**

Append to the end of `commands/scan-source.md`:

```markdown

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
```

- [ ] **Step 2: Verify the sections landed correctly**

```bash
cd /Users/lian.trinh/SourceCode/setup-qa-plugin/lian-qa-plugin
grep -n "^## Update the cumulative index\|^## Report\|^## Rules" commands/scan-source.md
```
Expected: 3 lines, in order, and these are the last three `##` headings in
the file.

- [ ] **Step 3: Live smoke test — two scans, prove additive behavior**

```bash
SCRATCH=/private/tmp/scan-source-cumulative-smoke
rm -rf "$SCRATCH" && mkdir -p "$SCRATCH/backend-repo/controllers" "$SCRATCH/frontend-repo/src/components" "$SCRATCH/workspace"

cat > "$SCRATCH/backend-repo/package.json" <<'EOF'
{ "name": "svc", "dependencies": { "express": "^4.18.0" } }
EOF
cat > "$SCRATCH/backend-repo/controllers/healthController.js" <<'EOF'
router.get('/health', (req, res) => res.json({ ok: true }));
EOF

cat > "$SCRATCH/frontend-repo/package.json" <<'EOF'
{ "name": "web", "dependencies": { "react": "^18.2.0" } }
EOF
touch "$SCRATCH/frontend-repo/index.html" "$SCRATCH/frontend-repo/vite.config.js"
cat > "$SCRATCH/frontend-repo/src/components/Header.jsx" <<'EOF'
export const Header = () => <nav data-testid="main-nav" />;
EOF

cd "$SCRATCH/workspace"
```

**Run 1** — scan only the backend repo: manually follow the full command
flow against `$SCRATCH/backend-repo` (detect → confirm → check-existing →
scan/write backend → update index → report). Confirm
`.claude/docs/backend/` is created with real content and
`.claude/CLAUDE.md` gets one `## backend — .../backend-repo` entry.

```bash
ls .claude/docs/
cat .claude/CLAUDE.md
```
Expected: only `backend/` exists under `.claude/docs/`; `CLAUDE.md` has
exactly one entry.

**Run 2** — scan only the frontend repo, in the SAME `$SCRATCH/workspace`:
manually follow the full flow again against `$SCRATCH/frontend-repo`.

```bash
ls .claude/docs/
cat .claude/CLAUDE.md
diff <(echo) .claude/docs/backend/architecture.md > /dev/null && echo "backend/architecture.md still has content"
```
Expected: `.claude/docs/` now shows BOTH `backend/` and `frontend/`;
`backend/`'s files are untouched from Run 1 (still have content, not
emptied); `CLAUDE.md` now has TWO entries (backend's original entry
preserved, frontend's new entry appended).

```bash
rm -rf "$SCRATCH"
```

- [ ] **Step 4: Commit**

```bash
cd /Users/lian.trinh/SourceCode/setup-qa-plugin/lian-qa-plugin
git add commands/scan-source.md
git commit -m "Add /scan-source cumulative index, final report, and closing Rules — command complete"
```

---

## Task 6: Full smoke test (monorepo + no-match edge cases) + final self-review

**Files:**
- Test only — no modifications to `commands/scan-source.md` unless the
  smoke test surfaces a defect, in which case fix it in place and re-run.

- [ ] **Step 1: Smoke test the monorepo-ambiguity branch**

```bash
SCRATCH=/private/tmp/scan-source-monorepo-smoke
rm -rf "$SCRATCH" && mkdir -p "$SCRATCH/repo/controllers" "$SCRATCH/repo/src/components"
cat > "$SCRATCH/repo/package.json" <<'EOF'
{ "name": "monorepo", "dependencies": { "express": "^4.18.0", "react": "^18.2.0" } }
EOF
mkdir -p "$SCRATCH/repo/controllers" && touch "$SCRATCH/repo/controllers/apiController.js"
touch "$SCRATCH/repo/index.html" "$SCRATCH/repo/vite.config.js"
touch "$SCRATCH/repo/src/components/Widget.jsx"
```

Run the command's "Detect the source type" section against `$SCRATCH/repo`
manually. Confirm BOTH backend signals (`express` dependency,
`controllers/`) and frontend signals (`react` dependency, `index.html` +
`vite.config.js`, `src/components/`) are found, and that the command's
monorepo branch is what triggers (not the single-type branch). Walk through
picking option `3` (narrower sub-paths) and confirm the instructions say to
restart detection per sub-path.

```bash
rm -rf "$SCRATCH"
```

- [ ] **Step 2: Smoke test the no-match branch**

```bash
SCRATCH=/private/tmp/scan-source-nomatch-smoke
rm -rf "$SCRATCH" && mkdir -p "$SCRATCH/repo"
echo "just a readme, no manifest, no recognizable structure" > "$SCRATCH/repo/README.md"
```

Run "Detect the source type" against `$SCRATCH/repo`. Confirm zero signals
match, and the command's instructions correctly say to ask the user
directly (not guess).

```bash
rm -rf "$SCRATCH"
```

- [ ] **Step 3: Verify against the design's explicit scope boundary**

The command legitimately uses the word "autotest" throughout in normal
prose (e.g. "for writing autotests", "does not scan the autotest project
itself") and legitimately says "does not clone" / "never clones" to
describe what it deliberately does NOT do — neither is a scope violation.
What would be a real violation is an actual `autotest/` **output category**
(a fourth scanned-type alongside backend/frontend/mobile) or a live
`git clone` **instruction** telling the command to actually clone something.
Check for those precisely, not the bare words:

```bash
cd /Users/lian.trinh/SourceCode/setup-qa-plugin/lian-qa-plugin
grep -niE "docs/autotest|Scan and write — autotest|git clone|git checkout" commands/scan-source.md
grep -niE "Planner|Analyzer|FeatureGenerator|PomGenerator|StepsGenerator|TestRunner|SelectorHealer|QualityGatekeeper|speckit-specify|qa-spec-writing|qa:web|qa:native" commands/scan-source.md
```
Expected: **zero matches** on both. Any match is a real defect — remove it.

- [ ] **Step 4: Final self-review**

```bash
cd /Users/lian.trinh/SourceCode/setup-qa-plugin/lian-qa-plugin
grep -n "TBD\|TODO\|implement later\|fill in" commands/scan-source.md || echo "No placeholder markers found"
grep -n "Task [0-9]" commands/scan-source.md || echo "No stray Task-N references found"
grep -n "^## " commands/scan-source.md
wc -l commands/scan-source.md
```
Expected: "No placeholder markers found"; "No stray Task-N references
found"; the heading list shows, in order: `## Parse arguments`,
`## Detect the source type`, `## Check for existing content (per confirmed
type)`, `## Scan and write — backend`, `## Scan and write — frontend`,
`## Scan and write — mobile`, `## Update the cumulative index`,
`## Report`, `## Rules` (9 headings). Read through the full file once to
confirm it reads as one coherent document.

- [ ] **Step 5: Commit (only if Step 1, 2, or 3 required a fix)**

```bash
cd /Users/lian.trinh/SourceCode/setup-qa-plugin/lian-qa-plugin
git status
# If commands/scan-source.md shows as modified:
git add commands/scan-source.md
git commit -m "Fix /scan-source issue found in full smoke test"
```
If `git status` shows no changes, skip this step — nothing to commit.

# `/init` Command (Phase 1) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add `commands/init.md` to `lian-qa-plugin` with two modes — `/init new` scaffolds a fresh Playwright+BDD test workspace (MVP, no auth), `/init existing` scans a project's codebase and generates a `.claude/` knowledge base.

**Architecture:** A single prompt-driven command file (no companion `scripts/*.sh` — both modes require LLM judgment: asking the user questions, and in Mode B, reading and synthesizing understanding of arbitrary code. This differs from `/rename` and `/add-mcp`, which extracted deterministic logic into scripts). Mode A's file templates are fixed and embedded directly in the command. Mode B's output content is generated per-project by the executing agent following a fixed set of instructions and constraints.

**Tech Stack:** Markdown prompt command (Claude Code plugin convention, matches `commands/rename.md` / `commands/add-mcp.md` already in this repo). Scaffolded workspace uses `@playwright/test` + `playwright-bdd` + `allure-playwright` (+ WebdriverIO/Appium when mobile is selected).

## Global Constraints

- Reference design: `docs/superpowers/specs/2026-07-22-init-command-design.md` — this plan implements Phase 1 only (Mode A MVP + Mode B). Auth flow, `QA_ROOT`-equivalent resolver, and all pipeline agents (Planner, FeatureGenerator, etc.) are explicitly out of scope — do not add them.
- Mode A workspace root: `~/.claude-lian-qa/<name>/`, with an `.active` pointer file at `~/.claude-lian-qa/.active` (plain text, one line: the absolute workspace path). No multi-session locking, no migrate-from-cache logic.
- Mode A scaffolds flat directories at the workspace root: `features/`, `pages/`, `locators/`, `step-definitions/`, `specs/`, `auth/` — no `src/` wrapper (unlike the reference `qa-automation-framework`, which detects an existing convention; there's nothing to detect in a brand-new workspace).
- No automated git commands anywhere in the command (matches the convention already set by `/rename` and `/add-mcp` in this plugin) — the command never runs `git add`/`commit`/`push`.
- Every step that asks the user a question must explicitly wait for their reply before continuing — never assume an answer.
- Mode B: every fact written into `.claude/CLAUDE.md` or `.claude/docs/*.md` must be grounded in actual repo content. Where something can't be determined from the code, the literal string `not determined` is written — never a guess.

---

## Task 1: Command skeleton + mode routing

**Files:**
- Create: `commands/init.md`

**Interfaces:**
- Produces: the command's frontmatter (`name: init`, `argument-hint`) and the top-level routing logic that later tasks build on. Task 2 appends the Mode A body under a `## Mode A` heading; Task 5 appends the Mode B body under a `## Mode B` heading. Both headings are created as empty placeholders by this task so later tasks have an anchor to insert under.

- [ ] **Step 1: Write the command frontmatter and routing section**

Create `commands/init.md` with exactly this content:

```markdown
---
name: init
description: Scaffold a fresh QA automation workspace (mode "new") or scan an existing project's codebase to generate a .claude/ knowledge base (mode "existing"). Phase 1 of the lian-qa-plugin QA pipeline — see docs/superpowers/specs/2026-07-22-init-command-design.md.
argument-hint: "new [--no-install] | existing"
---

EXECUTE IMMEDIATELY.

## Resolve mode

```bash
set -- $ARGUMENTS
MODE="${1:-}"
NO_INSTALL="false"
for arg in "$@"; do
  [ "$arg" = "--no-install" ] && NO_INSTALL="true"
done
echo "MODE=$MODE NO_INSTALL=$NO_INSTALL"
```

- `$MODE` is `new` → Mode A. `$NO_INSTALL` (`true`/`false`) is used by Mode
  A's A6 step to decide whether to skip the final `npm install`.
- `$MODE` is `existing` → Mode B.
- Anything else (including empty) → ask the user:
  ```
  /init has two modes:
    1  new       — scaffold a fresh QA automation workspace
    2  existing  — scan this project's codebase and generate a .claude/ knowledge base

  Reply: 1 / 2 / new / existing
  ```
  Wait for the reply, then proceed to the matching mode below. If the reply
  doesn't match either, repeat the question — do not guess.

## Mode A

(placeholder — filled in by Task 2 and Task 3)

## Mode B

(placeholder — filled in by Task 5)
```

- [ ] **Step 2: Verify frontmatter parses**

Run:
```bash
cd /Users/lian.trinh/SourceCode/setup-qa-plugin/lian-qa-plugin
awk '/^---$/{c++} c==1' commands/init.md | grep -E '^(name|description|argument-hint):'
```
Expected output (3 lines, in this order):
```
name: init
description: Scaffold a fresh QA automation workspace (mode "new") or scan an existing project's codebase to generate a .claude/ knowledge base (mode "existing"). Phase 1 of the lian-qa-plugin QA pipeline — see docs/superpowers/specs/2026-07-22-init-command-design.md.
argument-hint: "new [--no-install] | existing"
```

- [ ] **Step 3: Commit**

```bash
cd /Users/lian.trinh/SourceCode/setup-qa-plugin/lian-qa-plugin
git add commands/init.md
git commit -m "Add /init command skeleton with mode routing"
```

---

## Task 2: Mode A — workspace setup questions (Steps 1-4)

**Files:**
- Modify: `commands/init.md` (replace the `## Mode A` placeholder body)

**Interfaces:**
- Consumes: nothing from other tasks (this is the start of Mode A's body).
- Produces: by the end of this section, the command has asked for a workspace
  name, created `$WORKSPACE = ~/.claude-lian-qa/<name>`, written
  `~/.claude-lian-qa/.active`, asked the platform question, and shown a
  scaffold-plan confirmation. Task 3 continues immediately after "On
  confirm, continue to Task 3's file-writing steps below."

- [ ] **Step 1: Replace the `## Mode A` placeholder**

In `commands/init.md`, replace:
```markdown
## Mode A

(placeholder — filled in by Task 2 and Task 3)
```
with:
```markdown
## Mode A

### A1 — Workspace name

Suggest a default from the current directory, then ask:
```bash
DEFAULT_NAME=$(basename "$PWD" | tr '[:upper:] ' '[:lower:]-')
echo "Suggested workspace name: ${DEFAULT_NAME:-my-qa-project}"
```

Send the user:
```
Name this QA workspace (lowercase letters, digits, dashes only).
It will live at: ~/.claude-lian-qa/<name>/

Suggested: <DEFAULT_NAME>

Reply with a name, or `ok` to use the suggestion.
```

**Wait for the reply.** Sanitize to `[a-z0-9-]` (lowercase, spaces → `-`).
Set `NAME`.

### A2 — Create the workspace

```bash
WORKSPACE="$HOME/.claude-lian-qa/$NAME"
if [ -d "$WORKSPACE" ] && [ -n "$(ls -A "$WORKSPACE" 2>/dev/null)" ]; then
  echo "EXISTS_NONEMPTY=$WORKSPACE"
else
  mkdir -p "$WORKSPACE"
  mkdir -p "$HOME/.claude-lian-qa"
  printf '%s\n' "$WORKSPACE" > "$HOME/.claude-lian-qa/.active"
  echo "✓ Workspace: $WORKSPACE"
  echo "✓ Marked active: $HOME/.claude-lian-qa/.active"
fi
```

If `EXISTS_NONEMPTY` printed, ask the user:
```
Workspace "<NAME>" already exists and is not empty: <WORKSPACE>

  1  Reuse this workspace (keep existing files, only create what's missing)
  2  Pick a different name
  3  Cancel

Reply: 1 / 2 / 3
```
Wait for reply. `1` → set `$WORKSPACE` and continue (Step-existence checks in
Task 3 handle "skip if exists"). `2` → go back to A1. `3` → stop with
"Cancelled — no files modified."

**Remember `$WORKSPACE` as an absolute path** — every subsequent step in Mode
A operates inside it (`cd "$WORKSPACE"` before any `mkdir`/`Write`/`npm`).

### A3 — Platform question

Ask the user:
```
Which platform will you be testing?
  w  Web only (Playwright)
  m  Mobile only (Appium + WebdriverIO)
  b  Both

Reply: w / m / b
```
Wait for the reply. Set `PLATFORM` to `w`, `m`, or `b`. If the reply doesn't
match, repeat the question.

### A4 — Confirm the scaffold plan

Show (substituting `$WORKSPACE`, `$PLATFORM`):
```
/init new will scaffold a workspace at: $WORKSPACE

Will create (only if missing):
  · features/, pages/, locators/, step-definitions/, specs/, auth/   (empty directories)
  · package.json          (Playwright + playwright-bdd + allure-playwright<mobile-suffix>)
  · playwright.config.ts  (TEST_MODULE scoping)
  · tsconfig.json
  · .gitignore
  · pages/BasePage.ts
  · qa-run-log.tsv        (empty, header only)

Then run: npm install   <(skipped if --no-install)>

Proceed? (y/n)
```
Where `<mobile-suffix>` is ` + WebdriverIO/Appium` when `$PLATFORM` is `m` or
`b`, else empty. Wait for the reply. `n` → stop with "Cancelled — no files
modified." `y` → continue to Task 3's steps.
```

- [ ] **Step 2: Verify the section landed correctly**

```bash
cd /Users/lian.trinh/SourceCode/setup-qa-plugin/lian-qa-plugin
grep -n "^### A1\|^### A2\|^### A3\|^### A4" commands/init.md
```
Expected: 4 lines, one per heading, in order A1 → A2 → A3 → A4.

- [ ] **Step 3: Commit**

```bash
cd /Users/lian.trinh/SourceCode/setup-qa-plugin/lian-qa-plugin
git add commands/init.md
git commit -m "Add /init Mode A workspace setup questions (A1-A4)"
```

---

## Task 3: Mode A — file scaffolding (Step 5) + templates

**Files:**
- Modify: `commands/init.md` (append after A4, before Mode B placeholder)
- Test: a scratch directory under the plugin's scratchpad (not committed) —
  used only to validate the embedded templates are syntactically valid.

**Interfaces:**
- Consumes: `$WORKSPACE`, `$PLATFORM`, `$NAME` from Task 2.
- Produces: the exact content of every scaffolded file, which Task 4's
  smoke test relies on to actually run `npm install` end-to-end.

- [ ] **Step 1: Append the A5 file-writing section**

In `commands/init.md`, insert the following immediately after the A4 block
(still inside `## Mode A`, before the `## Mode B` heading):

```markdown
### A5 — Create directories and files

```bash
cd "$WORKSPACE"
mkdir -p features pages locators step-definitions specs auth
echo "✓ Directories ready under $WORKSPACE"
```

For each file below: if it already exists AND the user picked reuse-mode in
A2, skip it and print `⊘ Skipped <file> (already exists)`. Otherwise write it
with the **Write** tool using the exact content shown.

**`package.json`** (substitute `<NAME>` with the sanitized workspace name from A1):
```json
{
  "name": "<NAME>",
  "version": "0.1.0",
  "private": true,
  "description": "QA automation tests scaffolded by lian-qa-plugin",
  "scripts": {
    "bdd-gen": "bddgen",
    "test": "playwright test",
    "test:headed": "playwright test --headed",
    "test:debug": "playwright test --debug",
    "test:ui": "playwright test --ui",
    "test:tag": "playwright test --grep",
    "allure:generate": "allure generate allure-results --clean -o allure-report",
    "test:report": "npm run allure:generate && allure open allure-report"
  },
  "devDependencies": {
    "@playwright/test": "^1.60.0",
    "@types/node": "^25.5.0",
    "allure-commandline": "^2.38.0",
    "allure-playwright": "^2.15.1",
    "playwright-bdd": "^8.5.0",
    "typescript": "^6.0.2"
  }
}
```

If `$PLATFORM` is `m` or `b`, merge these into the `scripts` and
`devDependencies` blocks above before writing:
```json
"scripts": {
  "test:mobile": "wdio run wdio.conf.ts",
  "test:mobile:android": "PLATFORM=android wdio run wdio.conf.ts",
  "test:mobile:ios": "PLATFORM=ios wdio run wdio.conf.ts"
},
"devDependencies": {
  "@cucumber/cucumber": "^12.7.0",
  "@wdio/allure-reporter": "^9.27.0",
  "@wdio/appium-service": "^9.27.0",
  "@wdio/cli": "^9.27.0",
  "@wdio/cucumber-framework": "^9.27.0",
  "@wdio/globals": "^9.27.0",
  "@wdio/local-runner": "^9.27.0",
  "@wdio/spec-reporter": "^9.27.0",
  "webdriverio": "^9.27.0"
}
```

**`playwright.config.ts`:**
```typescript
import { defineConfig, devices } from '@playwright/test';
import { defineBddConfig } from 'playwright-bdd';

// TEST_MODULE scopes a session to a single feature file — parallel-safe.
// Unset → runs every feature in features/.
const TEST_MODULE = process.env.TEST_MODULE?.trim();

const featuresGlob = TEST_MODULE
  ? `features/${TEST_MODULE}.feature`
  : 'features/*.feature';

const mappingOutputDir = TEST_MODULE
  ? `mapping-steps/${TEST_MODULE}`
  : 'mapping-steps';

const testDir = defineBddConfig({
  features: featuresGlob,
  steps: ['step-definitions/*.ts'],
  outputDir: mappingOutputDir,
});

export default defineConfig({
  testDir,
  fullyParallel: true,
  forbidOnly: !!process.env.CI,
  retries: process.env.CI ? 2 : 0,
  workers: process.env.CI ? 1 : undefined,
  timeout: 30_000,
  expect: { timeout: 5_000 },
  reporter: [
    ['list'],
    ['allure-playwright'],
  ],
  use: {
    trace: 'on-first-retry',
    screenshot: 'only-on-failure',
    video: 'retain-on-failure',
    actionTimeout: 10_000,
    baseURL: process.env.BASE_URL || 'http://localhost:4567/',
    testIdAttribute: 'data-testid',
  },
  projects: [
    {
      name: 'chromium',
      use: { ...devices['Desktop Chrome'] },
    },
  ],
});
```

**`tsconfig.json`:**
```json
{
  "compilerOptions": {
    "target": "ES2022",
    "lib": ["ES2022", "DOM"],
    "module": "commonjs",
    "moduleResolution": "node",
    "esModuleInterop": true,
    "allowSyntheticDefaultImports": true,
    "strict": true,
    "skipLibCheck": true,
    "forceConsistentCasingInFileNames": true,
    "resolveJsonModule": true,
    "declaration": true,
    "outDir": "./dist",
    "rootDir": "."
  },
  "include": ["**/*.ts"],
  "exclude": ["node_modules", "dist", "allure-report", "allure-results", "test-results"]
}
```

**`.gitignore`:**
```
node_modules/
dist/
allure-results/
allure-report/
test-results/
playwright-report/
auth/
.cache/
*.log
```

**`pages/BasePage.ts`:**
```typescript
import { Page } from '@playwright/test';

export class BasePage {
  constructor(protected readonly page: Page) {}

  async goto(path: string): Promise<void> {
    await this.page.goto(path);
  }
}
```

**`qa-run-log.tsv`:**
```
timestamp	module	platform	action	status	notes
```
(single header line, no trailing blank scenarios — real rows get appended by
later phases)
```

- [ ] **Step 2: Verify the section landed correctly**

```bash
cd /Users/lian.trinh/SourceCode/setup-qa-plugin/lian-qa-plugin
grep -n "^### A5" commands/init.md
grep -c '```json\|```typescript' commands/init.md
```
Expected: one `### A5` line; at least 5 fenced `json`/`typescript` blocks
(package.json, mobile merge snippet, playwright.config.ts, tsconfig.json,
BasePage.ts).

- [ ] **Step 3: Validate the embedded templates are syntactically correct**

Render each template into a scratch directory and check it parses/compiles.
This is not part of the command's own execution — it's a one-time check that
the content we just wrote is valid.

```bash
SCRATCH=/private/tmp/claude-init-template-check
rm -rf "$SCRATCH" && mkdir -p "$SCRATCH/pages"
cd "$SCRATCH"
```

Copy the exact `package.json` content from Step 1 above into
`$SCRATCH/package.json`, the exact `tsconfig.json` into
`$SCRATCH/tsconfig.json`, the exact `playwright.config.ts` into
`$SCRATCH/playwright.config.ts`, and the exact `pages/BasePage.ts` into
`$SCRATCH/pages/BasePage.ts`. Then run:

```bash
cd "$SCRATCH"
python3 -c "import json; json.load(open('package.json')); print('package.json: valid JSON')"
python3 -c "import json; json.load(open('tsconfig.json')); print('tsconfig.json: valid JSON')"
npm install --no-save @playwright/test playwright-bdd typescript >/dev/null 2>&1
npx tsc --noEmit --skipLibCheck playwright.config.ts pages/BasePage.ts && echo "TypeScript files: OK"
```

Expected: `package.json: valid JSON`, `tsconfig.json: valid JSON`,
`TypeScript files: OK` (no compiler errors). If `tsc` reports errors, fix the
template in `commands/init.md` and re-run this step until it passes.

```bash
rm -rf "$SCRATCH"
```

- [ ] **Step 4: Commit**

```bash
cd /Users/lian.trinh/SourceCode/setup-qa-plugin/lian-qa-plugin
git add commands/init.md
git commit -m "Add /init Mode A file scaffolding templates (A5)"
```

---

## Task 4: Mode A — install + report, then full smoke test

**Files:**
- Modify: `commands/init.md` (append A6, close out `## Mode A`)

**Interfaces:**
- Consumes: everything from Task 2 and Task 3.
- Produces: the complete Mode A flow, ready to be exercised end-to-end by
  this task's smoke test.

- [ ] **Step 1: Append the A6 section**

Insert immediately after the A5 block (still inside `## Mode A`):

```markdown
### A6 — Install and report

```bash
cd "$WORKSPACE"
if [ "$NO_INSTALL" != "true" ]; then
  npm install
else
  echo "⊘ Skipped npm install (--no-install)"
fi
```

Report to the user:
```
✓ Workspace ready: $WORKSPACE
✓ Platform: <web / mobile / both>
✓ Files created (see list above)

No git command was run — this workspace has no git repo of its own yet;
review the files and run `git init` yourself if you want version control.
```
```

- [ ] **Step 2: Verify the full Mode A section is well-formed**

```bash
cd /Users/lian.trinh/SourceCode/setup-qa-plugin/lian-qa-plugin
awk '/^## Mode A$/{f=1} /^## Mode B$/{f=0} f' commands/init.md | grep -c "^### A"
```
Expected: `6` (A1 through A6).

- [ ] **Step 3: Full live smoke test of Mode A**

Manually walk through the Mode A flow in a real scratch workspace, exactly as
the command would when a user runs `/init new`. Use a fixed name to avoid any
prompt-waiting:

```bash
export HOME_BACKUP="$HOME"
export TEST_HOME=/private/tmp/claude-init-smoke-home
rm -rf "$TEST_HOME" && mkdir -p "$TEST_HOME"
NAME="smoke-test"
WORKSPACE="$TEST_HOME/.claude-lian-qa/$NAME"
PLATFORM="w"
mkdir -p "$WORKSPACE"
mkdir -p "$TEST_HOME/.claude-lian-qa"
printf '%s\n' "$WORKSPACE" > "$TEST_HOME/.claude-lian-qa/.active"
cd "$WORKSPACE"
mkdir -p features pages locators step-definitions specs auth
```

Then use the Write tool to create `package.json`, `playwright.config.ts`,
`tsconfig.json`, `.gitignore`, `pages/BasePage.ts`, `qa-run-log.tsv` in
`$WORKSPACE` with the exact content from Task 3 Step 1 (web-only variant —
`$PLATFORM` is `w`, so skip the mobile merge block), substituting `<NAME>`
with `smoke-test`.

```bash
cd "$WORKSPACE"
npm install
npm run bdd-gen 2>&1 | tail -5
ls features pages locators step-definitions specs auth
cat "$TEST_HOME/.claude-lian-qa/.active"
```

Expected:
- `npm install` completes without error.
- `npm run bdd-gen` runs (playwright-bdd generates an empty mapping dir since
  there are no `.feature` files yet — this is expected, not a failure).
- All 6 directories listed.
- `.active` file contains `$WORKSPACE`'s absolute path.

Clean up:
```bash
rm -rf "$TEST_HOME"
```

- [ ] **Step 4: Commit**

```bash
cd /Users/lian.trinh/SourceCode/setup-qa-plugin/lian-qa-plugin
git add commands/init.md
git commit -m "Add /init Mode A install + report (A6), complete Mode A flow"
```

---

## Task 5: Mode B — codebase scan and knowledge-base generation

**Files:**
- Modify: `commands/init.md` (replace the `## Mode B` placeholder body)

**Interfaces:**
- Consumes: nothing from other tasks (Mode B is fully independent of Mode A).
- Produces: the complete Mode B flow. Task 6 exercises it against a real
  project as a smoke test.

- [ ] **Step 1: Replace the `## Mode B` placeholder**

Replace:
```markdown
## Mode B

(placeholder — filled in by Task 5)
```
with:
```markdown
## Mode B

### B1 — Check for an existing `.claude/` folder

```bash
if [ -d .claude ]; then
  echo "EXISTS=.claude"
  find .claude -type f | sort
fi
```

If `EXISTS` printed, ask the user:
```
.claude/ already exists at the project root. Existing files are listed above.

  1  Overwrite — overwrite all 11 files
  2  Merge — only create missing files, keep existing ones
  3  Cancel

Reply: 1 / 2 / 3
```
Wait for reply. `3` → stop with "Cancelled — no files modified." `1` or `2` →
continue to B2, remembering the choice for B4 (whether to skip existing files).

### B2 — Scan the codebase

Read enough of the project to answer, for each item below, either a grounded
fact or "not determined". Do not guess. Do not invent framework names,
commands, or conventions not actually present in the repo.

- **Folder structure**: top-level layout (`ls -la` at root, then 2-3 levels
  into any test-related directories found).
- **Framework/language**: read `package.json` (or `requirements.txt`,
  `go.mod`, `pom.xml`, etc. — whatever dependency manifest exists) to
  identify the test framework, runner, and language/runtime.
- **Config**: any `playwright.config.*`, `wdio.conf.*`, `jest.config.*`,
  `cypress.config.*`, `.env.example`, or equivalent — read their actual
  content, don't assume defaults.
- **Dependencies**: the manifest's dependency list — note which are
  test-related vs. runtime.
- **Existing test examples**: find and read 2-3 real test files if any exist,
  to ground `patterns.md`, `coding-conventions.md`, `selectors-locators.md`,
  and `test-case-template.md` in actual code, not generic advice.
- **CI config**: `.github/workflows/*.yml`, `.gitlab-ci.yml`,
  `azure-pipelines.yml`, or equivalent, if present.

### B3 — Directory setup

```bash
mkdir -p .claude/docs
```

### B4 — Write the 11 files

For each file: if Mode B1's answer was `2` (merge) and the file already
exists, skip it and note `⊘ Skipped <file> (already exists)`. Otherwise write
it (Write tool).

**`.claude/CLAUDE.md`** — must cover, grounded in B2's findings:
- Framework/language overview (what you found, or "not determined")
- Project purpose (inferred from README/package description, or "not determined")
- Test commands: run all, run a single test, run by tag (the actual npm/yarn/
  make/etc. commands found in the manifest's `scripts`, or "not determined"
  if no test command exists)
- Required env variables (scan `.env.example`, config files, or CI workflow
  env blocks; list only ones you actually found)
- Setup instructions (install command + any prerequisite steps you found —
  e.g. `npx playwright install` if Playwright is a dependency)

**`.claude/docs/architecture.md`** — layers present (test runner, page/screen
object layer, fixtures, helpers, reporter, etc. — only the ones that actually
exist in this repo), the end-to-end flow of a single test run as you
understand it from the actual config/code, key libraries/plugins in use.

**`.claude/docs/structure.md`** — the real folder tree (from B2) with a
one-line purpose per top-level entry; state the organization convention
(by-feature / by-module / flat / "not determined") based on what's actually
there.

**`.claude/docs/patterns.md`** — design patterns actually used (Page Object
Model, Factory, fixtures, data-driven, etc.), each with a real code excerpt
copied from the repo. If no test examples exist, write "not determined — no
existing test examples found" instead of inventing patterns.

**`.claude/docs/coding-conventions.md`** — naming rules for files, classes,
methods, locators, variables, as observed in real files; format/lint config
if present (`.eslintrc`, `.prettierrc`, etc.); assertion/logging conventions
seen in actual test code.

**`.claude/docs/test-strategy.md`** — test categories actually present
(smoke/regression/e2e/api/etc. — inferred from folder names, tags, or CI job
names you actually found); write "not determined" for anything not evidenced
in the repo rather than inventing a generic strategy.

**`.claude/docs/test-case-template.md`** — a template derived from a real
existing test file. If none exists, write "not determined — no existing test
examples found" rather than inventing a generic template.

**`.claude/docs/selectors-locators.md`** — locator naming/selection
conventions and preferred selector types, based on actual locator code found.
"not determined" if no locator code exists.

**`.claude/docs/test-data.md`** — how test data/fixtures/mocks are managed,
test accounts, seed/reset process — grounded in actual fixture/data files
found. "not determined" for anything not evidenced.

**`.claude/docs/ci-cd.md`** — the actual pipeline found in B2 (triggers, jobs,
how to read reports), or "not determined — no CI config found".

**`.claude/docs/known-issues.md`** — flaky/skipped tests found (grep for
`.skip(`, `.only(`, `xit(`, `@skip`, `@disabled`, or equivalent markers) with
their reasons if stated in a comment; "not determined — none found" if the
scan turns up nothing.

### B5 — Report

List every file created (or skipped), each with a 1-2 line summary of its
actual content — not a generic description.
```

- [ ] **Step 2: Verify the section landed correctly**

```bash
cd /Users/lian.trinh/SourceCode/setup-qa-plugin/lian-qa-plugin
grep -n "^### B1\|^### B2\|^### B3\|^### B4\|^### B5" commands/init.md
grep -c "not determined" commands/init.md
```
Expected: 5 heading lines (B1-B5); at least 6 occurrences of "not determined"
(the guardrail phrase must appear across multiple file sections, not just
once).

- [ ] **Step 3: Commit**

```bash
cd /Users/lian.trinh/SourceCode/setup-qa-plugin/lian-qa-plugin
git add commands/init.md
git commit -m "Add /init Mode B codebase scan and knowledge-base generation"
```

---

## Task 6: Mode B live smoke test + final self-review

**Files:**
- Test only — no modifications to `commands/init.md` unless the smoke test
  surfaces a defect, in which case fix it in place and re-run.

- [ ] **Step 1: Run Mode B against a real project**

Use the sibling `claudecode-qa-automation-main/` checkout as the target (it's
a real Playwright+BDD project with existing tests, config, and CI-adjacent
docs — a good grounding test). Do this in a scratch copy so nothing in that
repo is modified:

```bash
SCRATCH=/private/tmp/claude-init-modeb-smoke
rm -rf "$SCRATCH"
cp -R /Users/lian.trinh/SourceCode/setup-qa-plugin/claudecode-qa-automation-main "$SCRATCH"
cd "$SCRATCH"
```

Manually execute Mode B's B1 through B5 exactly as written in
`commands/init.md` against this scratch copy (B1: `.claude/` doesn't exist
here, so no prompt — proceed straight to B2).

- [ ] **Step 2: Verify the output**

```bash
cd "$SCRATCH"
ls .claude/docs/ | sort
```
Expected: exactly 10 files — `architecture.md`, `ci-cd.md`,
`coding-conventions.md`, `known-issues.md`, `patterns.md`, `selectors-locators.md`,
`structure.md`, `test-case-template.md`, `test-data.md`, `test-strategy.md` —
plus `.claude/CLAUDE.md` (11 total).

```bash
grep -L "not determined" .claude/docs/*.md .claude/CLAUDE.md
```
Review this list by hand: every file here made a claim without the guardrail
phrase, so spot-check 2-3 of them against the real repo content (e.g. does
`architecture.md` actually describe the real Planner→Analyzer→...→
QualityGatekeeper pipeline from that repo's `CLAUDE.md`, not a generic
description?). If any claim doesn't trace to real repo content, that's a
defect — fix the B4 instructions in `commands/init.md` to be more explicit
about grounding, then re-run this task from Step 1.

```bash
rm -rf "$SCRATCH"
```

- [ ] **Step 3: Final self-review of `commands/init.md`**

```bash
cd /Users/lian.trinh/SourceCode/setup-qa-plugin/lian-qa-plugin
grep -n "TBD\|TODO\|implement later\|fill in" commands/init.md || echo "No placeholder markers found"
wc -l commands/init.md
```
Expected: "No placeholder markers found". Read through the full file once to
confirm Mode A and Mode B are both complete, self-contained, and match the
design spec (`docs/superpowers/specs/2026-07-22-init-command-design.md`).

- [ ] **Step 4: Commit (only if Step 2 required a fix)**

```bash
cd /Users/lian.trinh/SourceCode/setup-qa-plugin/lian-qa-plugin
git status
# If commands/init.md shows as modified:
git add commands/init.md
git commit -m "Fix /init Mode B grounding issue found in smoke test"
```
If `git status` shows no changes, skip this step — nothing to commit.

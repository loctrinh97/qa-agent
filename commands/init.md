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
Wait for reply. `1` → set `$WORKSPACE`, run:
```bash
mkdir -p "$HOME/.claude-lian-qa"
printf '%s\n' "$WORKSPACE" > "$HOME/.claude-lian-qa/.active"
```
then continue (Step-existence checks in A5 handle "skip if exists").
`2` → go back to A1. `3` → stop with "Cancelled — no files modified."

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
  · CLAUDE.md             (governance: no automated git commits — see below)

Then run: npm install   <(skipped if --no-install)>

Proceed? (y/n)
```
Where `<mobile-suffix>` is ` + WebdriverIO/Appium` when `$PLATFORM` is `m` or
`b`, else empty. Wait for the reply. `n` → stop with "Cancelled — no files
modified." `y` → continue to A5's steps.

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
    "ignoreDeprecations": "6.0",
    "types": ["node"],
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

**`CLAUDE.md`:**
```markdown
# <NAME> — QA Automation Workspace

This workspace was scaffolded by `/init new` (lian-qa-plugin).

## Governance

**No automated git operations.** No command in this workspace — nor any
Claude Code session working in it — should run `git add`, `git commit`,
`git push`, or any other git command that mutates history, on its own
initiative. Generate/edit files, then stop and let the human review with
`git status` / `git diff` and commit themselves, on their own terms and
timing.
```

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
- A `## Governance` section with this rule, verbatim, regardless of what
  else was found in the repo: "**No automated git operations.** No command
  in this project — nor any Claude Code session working in it — should run
  `git add`, `git commit`, `git push`, or any other git command that
  mutates history, on its own initiative. Generate/edit files, then stop
  and let the human review with `git status` / `git diff` and commit
  themselves, on their own terms and timing."

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

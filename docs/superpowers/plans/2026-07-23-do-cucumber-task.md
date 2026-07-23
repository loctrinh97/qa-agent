# `/do-cucumber-task` (Sub-project 1) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add `commands/do-cucumber-task.md` to `lian-qa-plugin` — fetches one CucumberStudio scenario, grounds it against this workspace's spec.md/scanned-source knowledge, verifies wording against real selectors when available, writes/updates `specs/NNN-<module>/spec.md`, and generates `features/<module>.feature`. Does not generate page objects, step definitions, or run tests (Sub-projects 2-5).

**Architecture:** A single prose-driven command file, same pattern as `commands/init.md`/`commands/spec.md`/`commands/scan-source.md` — no companion script, because every step requires LLM judgment (parsing a fetched scenario, resolving ambiguity, verifying wording). Reuses `/spec`'s spec-writing template and validation rubric **inline** (duplicated content, not a cross-command call — matches this plugin's established no-skill-extraction-yet convention).

**Tech Stack:** Markdown prompt command. Uses `ToolSearch` + the `cucumberstudio` MCP (required), and optionally `playwright`/`appium` MCP (only when live selector verification is chosen). No new local dependencies.

## Global Constraints

- Reference design: `docs/superpowers/specs/2026-07-23-do-cucumber-task-design.md`. This plan implements **Sub-project 1 of 5** only.
- **Explicitly out of scope — must not appear anywhere in `commands/do-cucumber-task.md`:** page object generation, locator file generation, step definition generation, test execution, any reference to `Planner`/`Analyzer`/`FeatureGenerator`/`PomGenerator`/`StepsGenerator`/`TestRunner`/`SelectorHealer`/`QualityGatekeeper` as named pipeline agents.
- **This command never embeds raw selectors (CSS/XPath/testid strings) in the generated `.feature` file.** Only verified (or explicitly unverified) UI copy/labels as quoted Gherkin step text.
- **Selector's role in this command is verification only** — confirming quoted wording is accurate, never producing a locator mapping.
- Platform detection (`backend`/`frontend`/`mobile`) is inferred from `.claude/docs/` (from `/scan-source`); ask the user directly only when ambiguous (multiple subfolders) or absent (no subfolders) — never guess.
- A live URL is asked for **only** when the platform is `web`/`frontend` AND no scanned frontend docs exist, OR the platform is web and scanned docs exist (in which case the user is asked to choose scanned-vs-live, not told a URL is mandatory). **Never** ask for a URL when platform is `backend` or `mobile`.
- The command never hard-blocks on a missing precondition check upfront — it resolves progressively (spec.md, or scanned docs, or a live URL/Appium connection offered in the moment). It blocks only when, after asking, truly nothing is available for a UI platform (web/mobile) — and even then it proceeds anyway, marking the feature file "unverified" rather than refusing to produce output (per the design's explicit "do not block" edge-case rows).
- `specs/NNN-<module>/spec.md` is always written or updated — reusing `/spec`'s numbering logic, template shape, `Source` metadata block (pointed at the CucumberStudio URL), and 5-dimension validation rubric, written inline in this command (not by invoking `/spec`).
- No automated git commands anywhere in the command.
- Every step that asks the user a question must explicitly wait for their reply before continuing.
- **MCP-dependent steps (the CucumberStudio fetch, live Playwright/Appium selector verification) cannot be exercised against real external services in this environment** — none of `cucumberstudio`/`playwright`/`appium` MCP servers are configured here, and there's no test CucumberStudio account. Every task below that touches an MCP call is verified via (a) structural review of the `ToolSearch` + "MCP not found → `/add-mcp <name>`" pattern (already proven correct in `/spec`'s task work) and (b) simulated scenario/selector data standing in for what a real fetch/inspection would return, so the downstream logic (module/platform resolution, wording verification, spec.md write, feature generation) gets genuinely exercised end-to-end even though the live MCP call itself is not.
- Command frontmatter: `name: do-cucumber-task`, `argument-hint: "<cucumberstudio-url>"`.

---

## Task 1: Command skeleton + URL parsing + CucumberStudio MCP fetch

**Files:**
- Create: `commands/do-cucumber-task.md`

**Interfaces:**
- Produces: the file's frontmatter and its first two sections ("Parse the CucumberStudio URL", "Resolve the CucumberStudio MCP tool" + "Fetch the scenario"). Task 2 appends module/platform determination immediately after; every later task appends after the previous, in file order.

- [ ] **Step 1: Write the command skeleton**

Create `commands/do-cucumber-task.md` with exactly this content:

```markdown
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
  confirm the URL is correct. Stop rather than inventing steps.
```

- [ ] **Step 2: Verify the file was created correctly**

```bash
cd /Users/lian.trinh/SourceCode/setup-qa-plugin/lian-qa-plugin
awk '/^---$/{c++} c==1' commands/do-cucumber-task.md | grep -E '^(name|description|argument-hint):'
grep -n "^## Parse the CucumberStudio URL\|^## Resolve the CucumberStudio MCP tool\|^## Fetch the scenario" commands/do-cucumber-task.md
```
Expected: the 3 frontmatter lines, then 3 heading lines in order.

- [ ] **Step 3: Verify the URL-parsing regex against valid and invalid URLs**

```bash
test_parse() {
  URL="$1"
  PROJECT_ID=$(echo "$URL" | grep -oE 'projects/[0-9]+' | grep -oE '[0-9]+')
  FOLDER_ID=$(echo "$URL" | grep -oE 'folders/[0-9]+' | grep -oE '[0-9]+')
  SCENARIO_ID=$(echo "$URL" | grep -oE 'scenarios/[0-9]+' | grep -oE '[0-9]+')
  echo "PROJECT_ID=$PROJECT_ID FOLDER_ID=$FOLDER_ID SCENARIO_ID=$SCENARIO_ID"
}
echo "=== valid ==="
test_parse "https://studio.cucumberstudio.com/projects/341786/test-plan/folders/4253324/scenarios/8115537"
echo "=== missing scenario id ==="
test_parse "https://studio.cucumberstudio.com/projects/341786/test-plan/folders/4253324"
echo "=== not a cucumberstudio url ==="
test_parse "https://example.com/foo/bar"
```
Expected: the valid URL prints `PROJECT_ID=341786 FOLDER_ID=4253324
SCENARIO_ID=8115537`; both invalid cases print at least one empty ID
(triggering the "doesn't look like a CucumberStudio scenario URL" stop
condition when this logic runs inside the actual command).

- [ ] **Step 4: Structural review of the MCP-fetch section**

Since no `cucumberstudio` MCP server is configured in this environment, this
step cannot call a real tool. Instead, verify the section's logic reads
correctly by inspection: confirm the "no tools found → tell the user to run
/add-mcp cucumberstudio" branch and the "never hardcode a specific tool
name" instruction are both present and match the pattern already proven
correct in `/spec`'s Step 0.2a (read `commands/spec.md`'s MCP-fallback
section for comparison — the phrasing/structure should be recognizably the
same discipline, not necessarily identical wording).

- [ ] **Step 5: Commit**

```bash
cd /Users/lian.trinh/SourceCode/setup-qa-plugin/lian-qa-plugin
git add commands/do-cucumber-task.md
git commit -m "Add /do-cucumber-task command skeleton with URL parsing and CucumberStudio fetch"
```

---

## Task 2: Module and platform determination

**Files:**
- Modify: `commands/do-cucumber-task.md` (append after Task 1's content)
- Test: a scratch directory with synthetic `.claude/docs/` fixtures.

**Interfaces:**
- Consumes: the fetched scenario's title/folder title from Task 1.
- Produces: `MODULE` and `PLATFORM`, consumed by Task 3's grounding-source
  resolution and Task 4's spec.md write.

- [ ] **Step 1: Append the module + platform sections**

Append to the end of `commands/do-cucumber-task.md`:

```markdown

## Determine the module name

Derive a candidate module name from the scenario's title or its parent
folder/feature title (sanitize to `[a-z0-9-]`, lowercase, spaces → `-`).

```
Scenario fetched: "<scenario title>" (folder: "<folder title>")
Suggested module name: <candidate>

Reply with a name, or `ok` to use the suggestion.
```
Wait for the reply. Set `MODULE`.

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
```

- [ ] **Step 2: Verify the sections landed correctly**

```bash
cd /Users/lian.trinh/SourceCode/setup-qa-plugin/lian-qa-plugin
grep -n "^## Determine the module name\|^## Determine the platform" commands/do-cucumber-task.md
```
Expected: 2 lines, in order.

- [ ] **Step 3: Live test — platform determination against real fixtures**

```bash
SCRATCH=/private/tmp/do-cucumber-platform-check
rm -rf "$SCRATCH" && cd /tmp && mkdir -p "$SCRATCH"

echo "=== case: only frontend scanned ==="
mkdir -p "$SCRATCH/case1/.claude/docs/frontend" && cd "$SCRATCH/case1" && ls .claude/docs/ 2>/dev/null

echo "=== case: frontend + mobile scanned (ambiguous) ==="
mkdir -p "$SCRATCH/case2/.claude/docs/frontend" "$SCRATCH/case2/.claude/docs/mobile" && cd "$SCRATCH/case2" && ls .claude/docs/ 2>/dev/null

echo "=== case: nothing scanned ==="
mkdir -p "$SCRATCH/case3" && cd "$SCRATCH/case3" && ls .claude/docs/ 2>/dev/null

rm -rf "$SCRATCH"
```
Expected: case1 lists only `frontend` (→ single-match branch, `PLATFORM=frontend`,
no question asked); case2 lists both `frontend` and `mobile` (→ ambiguous
branch, must ask); case3's `ls` fails/empty (→ none-present branch, must ask
directly). Manually confirm each case routes to the correct branch per the
appended section's text.

- [ ] **Step 4: Commit**

```bash
cd /Users/lian.trinh/SourceCode/setup-qa-plugin/lian-qa-plugin
git add commands/do-cucumber-task.md
git commit -m "Add /do-cucumber-task module and platform determination"
```

---

## Task 3: Grounding-source resolution + selector verification

**Files:**
- Modify: `commands/do-cucumber-task.md` (append after Task 2's content)
- Test: scratch directories simulating each platform branch.

**Interfaces:**
- Consumes: `PLATFORM` from Task 2.
- Produces: `SELECTOR_SOURCE` (`scanned` / `live` / `none`) and, when
  verification ran, corrected step wording — consumed by Task 4's spec.md
  write and Task 5's feature generation.

- [ ] **Step 1: Append the grounding-source + verification sections**

Append to the end of `commands/do-cucumber-task.md`:

```markdown

## Resolve the grounding/selector source

Branch on `PLATFORM`:

**`backend`** — no selector step. Use `specs/*/spec.md` and/or
`.claude/docs/backend/` content directly for business-logic grounding in
the spec.md write below. Skip straight to "Write/update spec.md".

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

**`web`**:
```bash
ls .claude/docs/frontend/components.md 2>/dev/null
```
- Exists → ask: "Use the scanned .claude/docs/frontend/components.md, or a
  live website URL instead? Reply: scanned / live". Wait for the reply.
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
```

- [ ] **Step 2: Verify the sections landed correctly**

```bash
cd /Users/lian.trinh/SourceCode/setup-qa-plugin/lian-qa-plugin
grep -n "^## Resolve the grounding/selector source\|^## Verify step wording" commands/do-cucumber-task.md
```
Expected: 2 lines, in order.

- [ ] **Step 3: Verify a live URL is never solicited for backend/mobile**

```bash
cd /Users/lian.trinh/SourceCode/setup-qa-plugin/lian-qa-plugin
awk '/\*\*`backend`\*\*/,/\*\*`mobile`\*\*/' commands/do-cucumber-task.md | grep -i "url" || echo "no URL mention in the backend branch — correct"
awk '/\*\*`mobile`\*\*/,/\*\*`web`\*\*/' commands/do-cucumber-task.md | grep -i "live website URL" || echo "no live-website-URL mention in the mobile branch — correct"
```
Expected: both echo their "correct" message — confirms the design's
"never ask for a URL when platform is backend or mobile" constraint is
honored in the actual text.

- [ ] **Step 4: Simulated verification test — web, with a scanned-docs mismatch**

This step simulates what the "Verify step wording" section would do with
real scanned data, without needing a live MCP call:

```bash
SCRATCH=/private/tmp/do-cucumber-verify-check
rm -rf "$SCRATCH" && mkdir -p "$SCRATCH/.claude/docs/frontend"
cat > "$SCRATCH/.claude/docs/frontend/components.md" <<'EOF'
## LoginButton
data-testid="login-submit-button" — real label: "Sign In"
EOF
cd "$SCRATCH"
```

Manually walk through "Verify step wording" as if the fetched CucumberStudio
scenario had a step `When I click "Login"` and the resolved
`SELECTOR_SOURCE=scanned` (from `.claude/docs/frontend/components.md`
above). Per the section's instructions, the real wording ("Sign In") must
be used instead of CucumberStudio's stale wording ("Login"), and the
discrepancy must be noted for the final report.

```bash
rm -rf "$SCRATCH"
```
Expected: your walkthrough concludes the step should read `When I click
"Sign In"` (not "Login"), with a discrepancy note recorded — confirming the
instructions produce the correct correction, not a silent pass-through of
the stale text.

- [ ] **Step 5: Commit**

```bash
cd /Users/lian.trinh/SourceCode/setup-qa-plugin/lian-qa-plugin
git add commands/do-cucumber-task.md
git commit -m "Add /do-cucumber-task grounding-source resolution and step-wording verification"
```

---

## Task 4: spec.md write/update (reusing `/spec`'s template + rubric inline)

**Files:**
- Modify: `commands/do-cucumber-task.md` (append after Task 3's content)
- Test: a scratch workspace with a `specs/` directory.

**Interfaces:**
- Consumes: `MODULE`, `PLATFORM`, the fetched scenario's steps, and
  (optionally) verified wording from Task 3.
- Produces: `specs/<NNN>-<MODULE>/spec.md` on disk — consumed by Task 5's
  feature-file traceability comment.

- [ ] **Step 1: Append the spec.md write + rubric sections**

Append to the end of `commands/do-cucumber-task.md`:

```markdown

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
```

- [ ] **Step 2: Verify the sections landed correctly**

```bash
cd /Users/lian.trinh/SourceCode/setup-qa-plugin/lian-qa-plugin
grep -n "^## Write/update spec.md\|^## Validate the spec" commands/do-cucumber-task.md
```
Expected: 2 lines, in order.

- [ ] **Step 3: Live smoke test — write a real spec.md from simulated scenario data**

```bash
SCRATCH=/private/tmp/do-cucumber-spec-smoke
rm -rf "$SCRATCH" && mkdir -p "$SCRATCH/specs"
cd "$SCRATCH"
```

Simulate a fetched CucumberStudio scenario for module `checkout-payment`
(`PLATFORM=web`, no verified-wording changes needed) with 2 Given/When/Then
groups of your own realistic construction (e.g. "successful payment" and
"declined payment"). Follow "Write/update spec.md" manually: `specs/` is
empty so `NNN=001`. Use the Write tool to create
`specs/001-checkout-payment/spec.md` with real content matching the
template — including the `**Source**: CucumberStudio — [...]` line pointing
at a fake-but-realistic CucumberStudio URL.

```bash
cat specs/001-checkout-payment/spec.md
```
Expected: a real, readable spec file with the `Source`/`Source Last
Synced` lines, 2 ACs, and a Prompt History entry mentioning
`/do-cucumber-task`.

Manually score it against the 5-dimension rubric table — confirm 5/5 given
2 concrete, traceable ACs.

```bash
rm -rf "$SCRATCH"
```

- [ ] **Step 4: Commit**

```bash
cd /Users/lian.trinh/SourceCode/setup-qa-plugin/lian-qa-plugin
git add commands/do-cucumber-task.md
git commit -m "Add /do-cucumber-task spec.md write/update and validation rubric"
```

---

## Task 5: Feature file generation + final report + Rules

**Files:**
- Modify: `commands/do-cucumber-task.md` (append after Task 4's content —
  this is the last section, completing the file)
- Test: a scratch workspace, both the verified and unverified cases.

**Interfaces:**
- Consumes: `MODULE`, `NNN` (from Task 4), verified/unverified step wording
  (from Task 3).
- Produces: `features/<MODULE>.feature` — the complete command file.

- [ ] **Step 1: Append the feature-generation + report + Rules sections**

Append to the end of `commands/do-cucumber-task.md`:

```markdown

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

Never write raw selectors (CSS/XPath/testid strings) into any step —
quoted text is UI copy only, verified or explicitly marked unverified.

## Report

```
Spec: specs/<NNN>-<MODULE>/spec.md
Feature: features/<MODULE>.feature
Platform: <PLATFORM>
Selector source: <scanned docs | live Playwright | live Appium | unverified>
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
```

- [ ] **Step 2: Verify the sections landed correctly**

```bash
cd /Users/lian.trinh/SourceCode/setup-qa-plugin/lian-qa-plugin
grep -n "^## Generate the feature file\|^## Report\|^## Rules" commands/do-cucumber-task.md
```
Expected: 3 lines, in order, and these are the last three `##` headings in
the file.

- [ ] **Step 3: Live smoke test — verified feature file**

```bash
SCRATCH=/private/tmp/do-cucumber-feature-verified-smoke
rm -rf "$SCRATCH" && mkdir -p "$SCRATCH/features" "$SCRATCH/specs/001-checkout-payment"
cd "$SCRATCH"
```

Using the same `checkout-payment` scenario data from Task 4 Step 3 (2
ACs, `SELECTOR_SOURCE=scanned`, no wording discrepancies this time), write
`features/checkout-payment.feature` for real via the Write tool, following
the "Generate the feature file" section exactly — including the `# spec:
specs/001-checkout-payment/spec.md` traceability comment and 2 Scenario
blocks, and confirming NO `# unverified` marker line appears (since a
selector source was resolved).

```bash
cat features/checkout-payment.feature
grep -c "^Scenario:" features/checkout-payment.feature
grep -c "# unverified" features/checkout-payment.feature || echo "0 (correct — verified case)"
rm -rf "$SCRATCH"
```
Expected: 2 `Scenario:` lines; the unverified-marker grep finds nothing
(count 0), confirming the verified path doesn't carry the marker.

- [ ] **Step 4: Live smoke test — unverified feature file**

```bash
SCRATCH=/private/tmp/do-cucumber-feature-unverified-smoke
rm -rf "$SCRATCH" && mkdir -p "$SCRATCH/features" "$SCRATCH/specs/002-search-results"
cd "$SCRATCH"
```

Simulate a second scenario for module `search-results`, `PLATFORM=web`,
`SELECTOR_SOURCE=none` (no scanned docs, user replied `no` to the live-URL
question). Write `features/search-results.feature` for real, following the
"Generate the feature file" section's `SELECTOR_SOURCE=none` branch —
confirm the `# unverified — no selector source available` line appears
immediately after the spec-traceability comment.

```bash
cat features/search-results.feature
head -3 features/search-results.feature | grep -F "# unverified — no selector source available"
rm -rf "$SCRATCH"
```
Expected: the grep finds the exact marker line among the file's first 3
lines.

- [ ] **Step 5: Commit**

```bash
cd /Users/lian.trinh/SourceCode/setup-qa-plugin/lian-qa-plugin
git add commands/do-cucumber-task.md
git commit -m "Add /do-cucumber-task feature-file generation, report, and closing Rules — command complete"
```

---

## Task 6: Full smoke test (backend branch + scope review) + final self-review

**Files:**
- Test only — no modifications to `commands/do-cucumber-task.md` unless
  the smoke test surfaces a defect, in which case fix it in place and
  re-run.

- [ ] **Step 1: Smoke test the backend branch (no selector step at all)**

```bash
SCRATCH=/private/tmp/do-cucumber-backend-smoke
rm -rf "$SCRATCH" && mkdir -p "$SCRATCH/.claude/docs/backend" "$SCRATCH/specs" "$SCRATCH/features"
cat > "$SCRATCH/.claude/docs/backend/business-logic.md" <<'EOF'
Minimum order amount is $10 (MIN_ORDER_AMOUNT = 10).
EOF
cd "$SCRATCH"
```

Simulate a fetched scenario for module `order-minimum`, platform resolved
to `backend` (only `.claude/docs/backend/` present). Walk through "Resolve
the grounding/selector source" — confirm it routes straight to "Write/
update spec.md" with NO question asked about URLs, live inspection, or
selectors of any kind (per the backend branch's "no selector step" rule).
Then write a real `specs/001-order-minimum/spec.md` and
`features/order-minimum.feature` grounded in the business-logic content
above (referencing the real `$10` minimum), confirming the backend path
produces correct output without ever touching Playwright/Appium/live-URL
logic.

```bash
cat specs/001-order-minimum/spec.md
cat features/order-minimum.feature
rm -rf "$SCRATCH"
```
Expected: both files reference the real `$10`/`MIN_ORDER_AMOUNT` fact; no
mention of URLs or live inspection appears anywhere in either file (backend
scenarios don't carry a selector-source note the way web/mobile do, since
there's no selector step to report on).

- [ ] **Step 2: Verify against the design's explicit scope boundary**

```bash
cd /Users/lian.trinh/SourceCode/setup-qa-plugin/lian-qa-plugin
grep -niE "page object|locator file|step definition|Planner\b|Analyzer\b|FeatureGenerator|PomGenerator|StepsGenerator|TestRunner\b|SelectorHealer|QualityGatekeeper|git add|git commit|git push" commands/do-cucumber-task.md
```
Expected: **zero matches**. Any match is a real defect — one of the
explicitly out-of-scope items (page objects, locators, step definitions,
test execution, named pipeline agents, or an automated git command) leaked
into the file. If found, remove it and re-run this check.

- [ ] **Step 3: Final self-review**

```bash
cd /Users/lian.trinh/SourceCode/setup-qa-plugin/lian-qa-plugin
grep -n "TBD\|TODO\|implement later\|fill in" commands/do-cucumber-task.md || echo "No placeholder markers found"
grep -n "Task [0-9]" commands/do-cucumber-task.md || echo "No stray Task-N references found"
grep -n "^## " commands/do-cucumber-task.md
wc -l commands/do-cucumber-task.md
```
Expected: "No placeholder markers found"; "No stray Task-N references
found"; the heading list shows, in order: `## Parse the CucumberStudio
URL`, `## Resolve the CucumberStudio MCP tool`, `## Fetch the scenario`,
`## Determine the module name`, `## Determine the platform`, `## Resolve
the grounding/selector source`, `## Verify step wording`, `## Write/update
spec.md`, `## Validate the spec`, `## Generate the feature file`,
`## Report`, `## Rules` (12 headings). Read through the full file once to
confirm it reads as one coherent document end-to-end.

- [ ] **Step 4: Commit (only if Step 1 or Step 2 required a fix)**

```bash
cd /Users/lian.trinh/SourceCode/setup-qa-plugin/lian-qa-plugin
git status
# If commands/do-cucumber-task.md shows as modified:
git add commands/do-cucumber-task.md
git commit -m "Fix /do-cucumber-task issue found in full smoke test"
```
If `git status` shows no changes, skip this step — nothing to commit.

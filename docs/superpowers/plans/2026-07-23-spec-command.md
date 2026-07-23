# `/spec` Command Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add `commands/spec.md` to `lian-qa-plugin` — creates, updates, and validates a module spec at `specs/NNN-<module>/spec.md`, with source fetching (WebFetch-first, MCP fallback), a brainstorm step, a 5-dimension validation rubric, and source-drift reconciliation on update.

**Architecture:** A single prose-driven command file, same pattern as `commands/init.md` — no companion script, because every step requires LLM judgment (parsing an arbitrary source doc, brainstorming, scoring a rubric). Unlike `/init`'s two independent Mode A/Mode B sections, `/spec` is one linear flow — each task in this plan appends the next section to the end of the growing file rather than replacing a placeholder.

**Tech Stack:** Markdown prompt command (Claude Code plugin convention). Uses the built-in `WebFetch` tool, `ToolSearch` for MCP discovery, and `sha256sum` for source-drift detection. No new dependencies.

## Global Constraints

- Reference design: `docs/superpowers/specs/2026-07-23-spec-command-design.md`. This plan implements Step 0, Step 1, Step 2, Step 3, and Step 4 **(4A — source drift — only)**.
- **Explicitly out of scope — must not appear anywhere in `commands/spec.md`:** Step 4B (feature-file drift), any reference to `Planner`, `Analyzer`, `FeatureGenerator`, `PomGenerator`, `StepsGenerator`, `TestRunner`, `SelectorHealer`, `QualityGatekeeper`, the `speckit-specify` or `qa-spec-writing` skills, or any pointer to `/qa:web` / `/qa:native` or an equivalent test-generation command. None of that exists in this plugin yet.
- Spec location/numbering: `specs/<NNN>-<module>/spec.md`, where `NNN` is a zero-padded 3-digit number, one greater than the highest existing spec number (`000` + 1 = `001` when `specs/` is empty).
- No automated git commands anywhere in the command's own instructions. The **only** git text allowed in the file is the "After the spec is finalized" suggested-commit block, which must be explicitly marked display-only / never executed by the command itself.
- Every step that asks the user a question must explicitly wait for their reply before continuing — never assume an answer.
- Never hardcode Notion/Confluence/Jira credentials — rely on MCP OAuth only. Redact any secret/PII an MCP fetch returns before writing it into the spec.
- Command frontmatter: `name: spec`, `argument-hint: "<url-or-app-id | notion-url | confluence-url> [screen] [description]"`.

---

## Task 1: Command skeleton + argument parsing + existing-spec check

**Files:**
- Create: `commands/spec.md`

**Interfaces:**
- Produces: the file's frontmatter and its first two sections ("Parse arguments", "Check for existing spec"). Task 2 appends Step 0 immediately after this task's content; every later task appends after the previous task's content, in file order.

- [ ] **Step 1: Write the command skeleton**

Create `commands/spec.md` with exactly this content:

```markdown
---
name: spec
description: Create, update, or validate a module spec at specs/NNN-<module>/spec.md before running any test-generation pipeline. Tries WebFetch on a source link first (Notion/Confluence/Jira/web page); falls back to MCP only when auth-walled. Includes brainstorm, a 5-dimension validation rubric, and source-drift reconciliation on update.
argument-hint: "<url-or-app-id | notion-url | confluence-url> [screen] [description]"
---

EXECUTE IMMEDIATELY.

This is the **spec-first step** — run it before any test-generation command
to define what should be tested. Do NOT run any tests, invoke a test-
generation pipeline, or generate feature files/page objects/step
definitions — the spec is the only output of this command.

## Parse arguments

Detect the **source platform** from the first URL-shaped argument:

| Pattern | Source platform |
|---|---|
| `notion.so/`, `notion.site/`, `notion://<page-id>` | Notion |
| `atlassian.net/wiki/`, `confluence://<page-id>` | Confluence |
| `atlassian.net/browse/<ISSUE-KEY>` | Jira |
| `http://`, `https://` (web app under test) | Web app target URL |
| Java package name, APK path, `ios` keyword | Mobile app target |

Cases:
- **Source URL (Notion/Confluence/Jira) + target URL/app** → fetch source doc, use as spec input, note the target for later
- **Source URL only** → fetch source doc, write spec; no target app yet
- **Target only (no source)** → traditional flow: brainstorm + write from the user's description

Derive `module`:
- Target URL (web): last path segment → `module`
- Screen name (mobile): → `module`
- Source URL only: derived from the source page title (e.g. "Checkout Flow" → `checkout-flow`)

Sanitize `module` to `[a-z0-9-]` (lowercase, spaces → `-`).

## Check for existing spec

```bash
ls specs/*-<module>/ 2>/dev/null
```

- **Found**: read the existing spec. If it has a `**Source**:` metadata block → go to **Step 4 — Evolve**. Otherwise, this is a manually-authored spec — go to **Step 1 — Brainstorm** to gather the update.
- **Not found**: determine the next spec number:
  ```bash
  LAST=$(ls specs/ 2>/dev/null | sort | tail -1 | grep -oE '^[0-9]+')
  NNN=$(printf '%03d' $(( ${LAST:-0} + 1 )))
  ```
  If a source URL was provided → **Step 0 — Fetch from source**. Otherwise → **Step 1 — Brainstorm**.
```

- [ ] **Step 2: Verify the file was created correctly**

```bash
cd /Users/lian.trinh/SourceCode/setup-qa-plugin/lian-qa-plugin
awk '/^---$/{c++} c==1' commands/spec.md | grep -E '^(name|description|argument-hint):'
grep -n "^## Parse arguments\|^## Check for existing spec" commands/spec.md
```
Expected: the 3 frontmatter lines (`name: spec`, `description: ...`,
`argument-hint: ...`), then 2 heading lines in order.

- [ ] **Step 3: Verify the numbering bash is correct**

```bash
mkdir -p /private/tmp/spec-numbering-check/specs/002-login /private/tmp/spec-numbering-check/specs/007-checkout
cd /private/tmp/spec-numbering-check
LAST=$(ls specs/ 2>/dev/null | sort | tail -1 | grep -oE '^[0-9]+')
NNN=$(printf '%03d' $(( ${LAST:-0} + 1 )))
echo "NNN=$NNN"
cd /Users/lian.trinh/SourceCode/setup-qa-plugin/lian-qa-plugin
rm -rf /private/tmp/spec-numbering-check
```
Expected: `NNN=008` (one greater than the highest existing `007`). Also test
the empty case:
```bash
mkdir -p /private/tmp/spec-numbering-empty/specs
cd /private/tmp/spec-numbering-empty
LAST=$(ls specs/ 2>/dev/null | sort | tail -1 | grep -oE '^[0-9]+')
NNN=$(printf '%03d' $(( ${LAST:-0} + 1 )))
echo "NNN=$NNN"
cd /Users/lian.trinh/SourceCode/setup-qa-plugin/lian-qa-plugin
rm -rf /private/tmp/spec-numbering-empty
```
Expected: `NNN=001`.

- [ ] **Step 4: Commit**

```bash
cd /Users/lian.trinh/SourceCode/setup-qa-plugin/lian-qa-plugin
git add commands/spec.md
git commit -m "Add /spec command skeleton with argument parsing and existing-spec check"
```

---

## Task 2: Step 0 — Fetch from source

**Files:**
- Modify: `commands/spec.md` (append after Task 1's content)

**Interfaces:**
- Consumes: `module`, the detected source platform, and the source URL from
  Task 1's "Parse arguments".
- Produces: the extracted ACs/summary and the sha256 content hash, both
  referenced by Task 3 (Step 2 writes them into the spec) and Task 5
  (Step 4A compares against the stored hash on future updates).

- [ ] **Step 1: Append the Step 0 section**

Append to the end of `commands/spec.md`:

```markdown

## Step 0 — Fetch from source

Only runs if a source URL was provided.

**Default order — WebFetch first, MCP only as fallback.** Regardless of
platform (Notion / Confluence / Jira / generic web page), the first attempt
is always a plain `WebFetch` on the URL the user gave. Many pages are
publicly readable — there is no reason to pay the MCP authentication tax up
front. MCP only kicks in when WebFetch comes back auth-walled.

### 0.1 — Try WebFetch first (always)

```
WebFetch(url: <source_url>, prompt: "Extract the page title and any sections that look like acceptance criteria, requirements, user stories, scenarios, or test cases. Return content verbatim — do not paraphrase. Note clearly if the page redirects to login or requires sign-in.")
```

Examine the response:

| WebFetch response shape | Verdict | Next step |
|---|---|---|
| Substantive content returned (title + body text matching spec-shaped headings) | Public / accessible | Skip 0.2, go to **0.3 Extract** |
| Login page HTML / "Sign in" / "Log in" / OAuth redirect / 401 / 403 indicators | Auth-walled | Go to **0.2 MCP fallback** |
| Empty / very short response with no spec content | Ambiguous | Show the response excerpt, ask: "WebFetch returned <X>. Try MCP? (yes / no — paste content manually)" |
| Network error / DNS fail / timeout | Unreachable | Surface the error verbatim, ask the user to verify the URL |

Print one line so the user can follow the decision:
```
✓ WebFetch succeeded — using direct content (no MCP needed).
↺ WebFetch hit an auth wall — falling back to MCP.
⚠ WebFetch returned an ambiguous response — asking how to proceed.
```

### 0.2 — MCP fallback (only when WebFetch is auth-walled)

Skip entirely if 0.1 already succeeded.

**0.2a — Ensure authentication.** Use `ToolSearch` to discover available
tools for the detected platform (e.g. `ToolSearch(query: "notion", max_results: 10)`
or `ToolSearch(query: "atlassian", max_results: 10)`).

- If only an `*_authenticate`-style tool is returned → the MCP server is
  installed but not authenticated. Call it and share the OAuth URL:
  ```
  WebFetch couldn't read this page (auth-walled). To pull it via MCP, please
  complete authentication first:
    1. Open this URL in your browser: <oauth url>
    2. Sign in and approve access
    3. Come back here and reply "done"
  ```
  Wait for the reply, then re-run `ToolSearch` — fetch/search/list tools
  should now be available.
- If real fetch tools are already available → skip auth, go to 0.2b.
- If no MCP server exists at all for this platform (private wiki, custom
  tracker) → tell the user:
  ```
  WebFetch hit an auth wall and no MCP server is available for this platform.
  Options:
    1. Paste the page content directly here, then reply "use pasted content"
    2. Make the page publicly readable, then reply "retry"
    3. Install an MCP server for this platform (e.g. /add-mcp jira covers
       Confluence + Jira) and reply "retry"
  ```

**0.2b — Fetch via MCP.** Identify the correct tool from the `ToolSearch`
result — never hardcode a specific tool name, since the installed MCP server
varies by user. Extract the page ID from the URL (Notion: last segment after
the final `-`; Confluence: numeric ID in `/pages/<id>/`; Jira: the issue key
in `/browse/<KEY-123>`). Call the fetch tool. Expect `title`, `content`,
`url` in the result.

### 0.3 — Extract acceptance criteria from the content

Scan the (unstructured) content for, in order of preference:
1. Headings named "Acceptance Criteria", "Requirements", "User Stories", "Scenarios", "Test Cases"
2. Numbered/bulleted lists matching `AC1`, `AC2:`, `FR-001`, `TC-01`, `Given ... When ... Then ...`, `As a <role>, I want <action>, so that <outcome>`
3. Tables with columns like `Scenario | Given | When | Then` or `ID | Description | Expected`
4. Callout/note blocks marked as spec/requirement
5. "Out of scope" / "Not included" sections → preserve as Assumptions

Ignore: design mockups/images/Figma links (note but don't extract), comments/
discussion threads, marketing copy, implementation details (DB schema, API design).

Build a structured summary and show it to the user:
```
Source: <platform> — "<page title>"
URL: <url>
Extracted:
  - User stories: <count>
  - Acceptance criteria: <count>
  - Edge cases: <count>
  - Out of scope items: <count>

Sample ACs:
  1. Given <...>, When <...>, Then <...>
  2. ...

Unclear items (need brainstorm):
  - "<ambiguous item>"
```
Ask: "Is this extraction accurate? (yes / edit / re-fetch)"
- `yes` → Step 1
- `edit` → incorporate corrections, show the summary again
- `re-fetch` → wait for the user to update the source and reply "done", re-run 0.2

### 0.4 — Compute content hash

```bash
echo "<page content>" | sha256sum | awk '{print $1}'
```
Store this hash — it goes into the spec's `Source` metadata block in Step 2
and is compared again in Step 4A on future updates.
```

- [ ] **Step 2: Verify the section landed correctly**

```bash
cd /Users/lian.trinh/SourceCode/setup-qa-plugin/lian-qa-plugin
grep -n "^## Step 0\|^### 0.1\|^### 0.2\|^### 0.3\|^### 0.4" commands/spec.md
```
Expected: 5 lines — `## Step 0`, `### 0.1`, `### 0.2`, `### 0.3`, `### 0.4`,
in that order.

- [ ] **Step 3: Verify WebFetch behaves as Step 0.1 describes, on a real URL**

```
WebFetch(url: "https://example.com", prompt: "Extract the page title and any sections that look like acceptance criteria, requirements, user stories, scenarios, or test cases. Return content verbatim — do not paraphrase. Note clearly if the page redirects to login or requires sign-in.")
```
Expected: substantive content returned (this page's title is "Example
Domain" with a short body paragraph — no login/auth-wall signals). This
confirms the "Public / accessible" row of Step 0.1's table against a real
response shape.

**If the WebFetch tool itself errors** (e.g. a backend model error unrelated
to the target URL — this has happened before in this environment), do not
treat it as a defect in the command's design. Note it in your report as an
environment issue, and instead verify Step 0.1's table logic by inspection:
confirm the four response-shape rows are mutually exclusive and cover
"substantive content" / "auth-wall signals" / "empty-or-short" / "network
error" with no gap.

- [ ] **Step 4: Verify the content-hash step is deterministic**

```bash
echo "sample page content for hashing" | sha256sum | awk '{print $1}'
echo "sample page content for hashing" | sha256sum | awk '{print $1}'
echo "different content" | sha256sum | awk '{print $1}'
```
Expected: the first two commands print the identical hash; the third prints
a different hash. Confirms Step 0.4 and Step 4A's later drift comparison
will work correctly.

- [ ] **Step 5: Commit**

```bash
cd /Users/lian.trinh/SourceCode/setup-qa-plugin/lian-qa-plugin
git add commands/spec.md
git commit -m "Add /spec Step 0: fetch from source (WebFetch-first, MCP fallback)"
```

---

## Task 3: Step 1 (brainstorm) + Step 2 (write the spec)

**Files:**
- Modify: `commands/spec.md` (append after Task 2's content)
- Test: a scratch directory with a `specs/` subdirectory, simulating a QA
  workspace (not committed).

**Interfaces:**
- Consumes: the module name and ACs (from Step 0, or from the user directly
  when there's no source).
- Produces: `specs/<NNN>-<module>/spec.md` on disk — the artifact Task 4's
  rubric scores and Task 5's Step 4A reads back on future updates.

- [ ] **Step 1: Append the Step 1 + Step 2 sections**

Append to the end of `commands/spec.md`:

```markdown

## Step 1 — Brainstorm (refine before writing)

**Skip this step if**:
- Step 0 produced clear, structured ACs with no "unclear items"
- The user supplied 3+ explicit acceptance criteria in the description

**Otherwise** — ask up to 5 focused questions, one at a time, waiting for
each reply before the next. Cover only what's still unclear:
- Primary user goal on this screen/page
- Success vs. failure paths
- Edge cases
- Form validation / conditional UI / multi-step flows
- Out-of-scope items

## Step 2 — Write the spec

Write `specs/<NNN>-<module>/spec.md` (create the directory if it doesn't
exist) with this structure:

```markdown
# Spec: <module>

**Status**: Draft
**Platform**: <web | mobile-android | mobile-ios>
**Target**: <target_url or app_id, or "not yet provided">
**Screen**: <screen_name, if mobile>

## Description

<user's description + brainstorm answers, in prose>

## User Stories

### US1: <story title>

**Priority**: <P0/P1/P2, if stated, else "not specified">

- **AC1**: Given <...>, When <...>, Then <...>
- **AC2**: Given <...>, When <...>, Then <...>

## Assumptions / Out of scope

- <item>

## Prompt History

- <ISO timestamp> — <one-line summary of this authoring/update session>
```

If a source was used in Step 0, append this block immediately below the
`**Status**:` line:
```markdown
**Source**: <platform> — [<page title>](<source_url>)
**Source Last Synced**: <ISO timestamp>
**Source Content Hash**: sha256:<hash from 0.4>
```
Omit the block entirely if no source was used.

Show the spec summary:
```
Spec: specs/<NNN>-<module>/spec.md
Source: <platform, or "manual"> — <title, or "user description">

| # | User Story | Priority | Scenarios |
|---|---|---|---|
| 1 | <title> | <priority> | <AC count> |
```
```

- [ ] **Step 2: Verify the sections landed correctly**

```bash
cd /Users/lian.trinh/SourceCode/setup-qa-plugin/lian-qa-plugin
grep -n "^## Step 1\|^## Step 2" commands/spec.md
```
Expected: 2 lines, `## Step 1` before `## Step 2`.

- [ ] **Step 3: Live smoke test — write a real spec.md in a scratch workspace**

```bash
SCRATCH=/private/tmp/spec-write-smoke
rm -rf "$SCRATCH" && mkdir -p "$SCRATCH/specs"
cd "$SCRATCH"
```

Follow the Task/Check-for-existing-spec flow manually for module `checkout`
(target-only case, no source — matches the "Target only" case from Task 1's
Parse-arguments section): `specs/` is empty, so `NNN=001`. Skip Step 0 (no
source). Skip Step 1's brainstorm by supplying 3 explicit ACs yourself (per
the brief's skip condition). Then execute Step 2: use the Write tool to
create `specs/001-checkout/spec.md` with real, filled-in content for a
"checkout flow" module — 1 user story, 3 ACs, no `Source` block (since no
source was used).

```bash
cat specs/001-checkout/spec.md
```
Expected: a real, readable spec file matching the Step 2 template — `**Status**: Draft`, no `**Source**:` line, one `## User Stories` section with
3 `AC` bullets, a `## Prompt History` entry with today's date.

```bash
rm -rf "$SCRATCH"
```

- [ ] **Step 4: Commit**

```bash
cd /Users/lian.trinh/SourceCode/setup-qa-plugin/lian-qa-plugin
git add commands/spec.md
git commit -m "Add /spec Step 1 (brainstorm) and Step 2 (write the spec)"
```

---

## Task 4: Step 3 (validation rubric) + final report

**Files:**
- Modify: `commands/spec.md` (append after Task 3's content)

**Interfaces:**
- Consumes: the spec file written by Task 3's Step 2.
- Produces: the rubric score and the final user-facing report, including the
  display-only git suggestion.

- [ ] **Step 1: Append the Step 3 + final-report sections**

Append to the end of `commands/spec.md`:

```markdown

## Step 3 — Validate the spec

Score against these 5 dimensions (pass=1/fail=0 each):

| Dimension | Passes when |
|---|---|
| Completeness | Every stated user goal has at least one AC; no obvious gap between the description and the scenarios |
| Clarity | Each AC is unambiguous — a different reader would write the same scenario from it |
| Testability | Each AC has a concrete, observable Given/When/Then — not a vague goal statement |
| Independence | Scenarios don't depend on execution order or hidden shared state |
| Traceability | Every AC traces to something the user said or the source doc contained — nothing invented |

- **5/5** → spec is ready, proceed to the final report below.
- **3-4/5** → show the failing dimension(s) with a quoted example from the
  spec, fix inline now, re-score.
- **<3/5** → not ready — go back to **Step 1** for more input. Do not ship
  a spec scoring below 3/5.

## After the spec is finalized

Show:
```
Spec saved to specs/<NNN>-<module>/spec.md
Scenarios: <total count> across <story count> user stories

The test-generation pipeline (feature files, page objects, step definitions)
is a future phase of this plugin — not available yet. This spec is ready to
feed it once that phase ships.
```

Suggested commit (**display-only** — print for the user to run themselves;
never execute it):
```bash
git add specs/<NNN>-<module>/spec.md
git commit -m "docs(spec): add spec for <module> (source: <platform or manual>)"
```
```

- [ ] **Step 2: Verify the sections landed correctly**

```bash
cd /Users/lian.trinh/SourceCode/setup-qa-plugin/lian-qa-plugin
grep -n "^## Step 3\|^## After the spec is finalized" commands/spec.md
```
Expected: 2 lines, in order.

- [ ] **Step 3: Verify the display-only git block is not framed as executable**

```bash
grep -n "display-only" commands/spec.md
grep -B3 "git add specs" commands/spec.md
```
Expected: the "display-only" annotation appears immediately before the
`git add`/`git commit` block, and the surrounding text says "print for the
user to run themselves; never execute it" — not an instruction telling the
command to run it.

- [ ] **Step 4: Score the Task 3 smoke-test spec against the rubric by hand**

Re-create the scratch spec from Task 3 Step 3 (or reuse its content from
memory) and manually score it against the 5-dimension table: does it score
5/5 given 3 concrete ACs with clear Given/When/Then, no invented content,
and independent scenarios? Confirm the rubric table's wording is
unambiguous enough to produce the same score a second time.

- [ ] **Step 5: Commit**

```bash
cd /Users/lian.trinh/SourceCode/setup-qa-plugin/lian-qa-plugin
git add commands/spec.md
git commit -m "Add /spec Step 3 (validation rubric) and final report"
```

---

## Task 5: Step 4 (Evolve — source drift only) + closing Rules

**Files:**
- Modify: `commands/spec.md` (append after Task 4's content — this is the
  last section in the file)

**Interfaces:**
- Consumes: an existing spec with a `**Source**:` metadata block (from
  Task 3's Step 2), plus a fresh Step-0 re-fetch and hash.
- Produces: the complete command file.

- [ ] **Step 1: Append the Step 4 + Rules sections**

Append to the end of `commands/spec.md`:

```markdown

## Step 4 — Evolve (source drift only)

Entered only when Step "Check for existing spec" found an existing spec with
a `**Source**:` metadata block.

1. Re-fetch the source page using the stored URL (Step 0.1-0.2).
2. Compute the new content hash (Step 0.4).
3. Compare to the stored `Source Content Hash`.

**Hashes match** → tell the user: "Source unchanged since <Source Last Synced>."
Done — no spec changes needed.

**Hashes differ**:
```
Source has changed since last sync.

Old hash: sha256:<old>  (synced <old date>)
New hash: sha256:<new>  (fetched now)

Changes detected:
  + Added AC: "<...>"
  - Removed AC: "<...>"
  ~ Modified AC: "<old text>" → "<new text>"

Update the spec to match? (yes / no / selective)
```
- `yes` → apply all changes
- `selective` → ask which changes to apply, one at a time
- `no` → leave the spec as-is, note the drift in the Prompt History entry instead

On any update: append a `Prompt History` entry, update `Source Content Hash`
and `Source Last Synced`, then re-run **Step 3** validation.

## Rules

- Do NOT run any tests, invoke a test-generation pipeline, or generate
  feature files / page objects / step definitions — the spec is the only
  output of this command.
- **Do NOT run `git add` / `git commit` yourself** — the block in "After the
  spec is finalized" is display-only text for the user.
- When updating an existing spec, never delete Prompt History entries — only
  append.
- **Never hardcode Notion/Confluence/Jira credentials** — rely on MCP OAuth only.
- If an MCP fetch returns private/secret information (API keys, internal
  URLs, personal data), redact it from the extracted ACs before writing the
  spec.
```

- [ ] **Step 2: Verify the sections landed correctly**

```bash
cd /Users/lian.trinh/SourceCode/setup-qa-plugin/lian-qa-plugin
grep -n "^## Step 4\|^## Rules" commands/spec.md
```
Expected: 2 lines, in order, and these are the last two `##` headings in the
file.

- [ ] **Step 3: Simulate the hash-match and hash-differ branches**

```bash
OLD_HASH=$(echo "Original page content about checkout." | sha256sum | awk '{print $1}')
NEW_HASH_SAME=$(echo "Original page content about checkout." | sha256sum | awk '{print $1}')
NEW_HASH_DIFFERENT=$(echo "Original page content about checkout, now with promo codes." | sha256sum | awk '{print $1}')
echo "match case:  $OLD_HASH == $NEW_HASH_SAME  -> $( [ "$OLD_HASH" = "$NEW_HASH_SAME" ] && echo MATCH || echo DIFFER )"
echo "differ case: $OLD_HASH vs $NEW_HASH_DIFFERENT -> $( [ "$OLD_HASH" = "$NEW_HASH_DIFFERENT" ] && echo MATCH || echo DIFFER )"
```
Expected: first line prints `MATCH`, second prints `DIFFER` — confirms the
Step 4 branch condition (`hashes match` vs. `hashes differ`) is correctly
computable from real hash values.

- [ ] **Step 4: Full-file final check**

```bash
cd /Users/lian.trinh/SourceCode/setup-qa-plugin/lian-qa-plugin
grep -n "^## " commands/spec.md
```
Expected: `## Parse arguments`, `## Check for existing spec`, `## Step 0 — Fetch from source`, `## Step 1 — Brainstorm (refine before writing)`, `## Step 2 — Write the spec`, `## Step 3 — Validate the spec`, `## After the spec is finalized`, `## Step 4 — Evolve (source drift only)`, `## Rules` — 9 headings, in this exact order.

- [ ] **Step 5: Commit**

```bash
cd /Users/lian.trinh/SourceCode/setup-qa-plugin/lian-qa-plugin
git add commands/spec.md
git commit -m "Add /spec Step 4 (source-drift evolve) and closing Rules — command complete"
```

---

## Task 6: Full live smoke test + final self-review

**Files:**
- Test only — no modifications to `commands/spec.md` unless the smoke test
  surfaces a defect, in which case fix it in place and re-run.

- [ ] **Step 1: End-to-end smoke test — new spec, then an update with source drift**

```bash
SCRATCH=/private/tmp/spec-full-smoke
rm -rf "$SCRATCH" && mkdir -p "$SCRATCH/specs"
cd "$SCRATCH"
```

**Part A — new spec with a real source URL.** Manually walk through
`commands/spec.md` end-to-end for input `https://example.com login-page`
(module `login-page`, source-only-shaped since `example.com` isn't Notion/
Confluence/Jira — treat it as the "web app target URL" case with no
separate source, i.e. the "Target only" case, OR alternatively treat it as
a generic web-page source per Step 0's "generic web page" support — pick
whichever the command's own Parse-arguments table actually routes it to,
and follow that path faithfully):
1. Parse arguments → determine module = `login-page`.
2. Check for existing spec → not found, `specs/` empty → `NNN=001`.
3. If routed through Step 0: real `WebFetch(url: "https://example.com", ...)`
   call, examine the response, show the extraction summary.
4. Step 1: skip or brainstorm depending on what Step 0 produced.
5. Step 2: write `specs/001-login-page/spec.md` for real, including a
   `Source` block with a real sha256 hash of the fetched content if Step 0
   ran.
6. Step 3: score the rubric by hand against the real file you just wrote.
7. Show the final report exactly as the command specifies.

**Part B — simulate an update with source drift.** Manually construct a
scenario: edit `specs/001-login-page/spec.md`'s `**Source Content Hash**`
field to a deliberately wrong value (simulating that the source changed
since last sync). Re-run Step 4: re-fetch `https://example.com` for real,
recompute the hash, compare to the (deliberately wrong) stored hash —
confirm the "Hashes differ" branch triggers, and walk through what the
command instructs you to show the user.

```bash
cat specs/001-login-page/spec.md
rm -rf "$SCRATCH"
```

**If the WebFetch tool itself errors** during this test (environment issue,
not a command defect — has happened before in this session), fall back to
using a hardcoded stand-in for "fetched content" (e.g. a fixed string) to
exercise the rest of the flow (extraction summary shape, spec writing, hash
compare), and note the WebFetch environment issue in your report rather
than treating it as a task failure.

- [ ] **Step 2: Verify against the design spec's explicit scope boundary**

```bash
cd /Users/lian.trinh/SourceCode/setup-qa-plugin/lian-qa-plugin
grep -niE "Planner|Analyzer|FeatureGenerator|PomGenerator|StepsGenerator|TestRunner|SelectorHealer|QualityGatekeeper|speckit-specify|qa-spec-writing|Step 4B|src/features|qa:web|qa:native" commands/spec.md
```
Expected: **zero matches**. Any match here is a real defect — one of the
explicitly out-of-scope items leaked into the file. If found, remove it and
re-run this check.

- [ ] **Step 3: Final self-review**

```bash
cd /Users/lian.trinh/SourceCode/setup-qa-plugin/lian-qa-plugin
grep -n "TBD\|TODO\|implement later\|fill in" commands/spec.md || echo "No placeholder markers found"
grep -n "^### 0\.\|^## Step [0-9]\|^## Parse\|^## Check\|^## After\|^## Rules" commands/spec.md
wc -l commands/spec.md
```
Expected: "No placeholder markers found"; the heading list matches Task 5
Step 4's expected 9 `##` headings plus the 4 `### 0.N` sub-headings from
Step 0, all present and in order. Read through the full file once to
confirm it reads as one coherent document, not a set of disjoint task
diffs (in particular: check there are no stray references to "Task N" —
this exact defect was found in `/init`'s final review and is worth
checking for here too).

- [ ] **Step 4: Commit (only if Step 1 or Step 2 required a fix)**

```bash
cd /Users/lian.trinh/SourceCode/setup-qa-plugin/lian-qa-plugin
git status
# If commands/spec.md shows as modified:
git add commands/spec.md
git commit -m "Fix /spec issue found in full smoke test"
```
If `git status` shows no changes, skip this step — nothing to commit.

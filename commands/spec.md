---
name: spec
description: Create, update, or validate a module spec at specs/NNN-<module>/spec.md before running any test-generation pipeline. Tries WebFetch on a source link first (Notion/Confluence/Jira/web page); falls back to MCP only when auth-walled. Includes brainstorm, a 5-dimension validation rubric, and source-drift reconciliation on update.
argument-hint: "<url-or-app-id | notion-url | confluence-url | jira-url> [screen] [description]"
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

**Disambiguating a single generic web-page URL** (not Notion/Confluence/Jira,
no second target argument given): ask the user before proceeding:
```
Is <url> a source document I should fetch and summarize (a spec/requirements
page), or the actual app/page under test?
  1  Source document — fetch it as the spec source
  2  App/page under test — this is the target, no separate source

Reply: 1 / 2
```
Wait for the reply. `1` → treat as the "Source URL only" case, proceed to
**Step 0**. `2` → treat as the "Target only" case, proceed to **Step 1**.

Derive `module`:
- Target URL (web): last path segment → `module`. If the URL has no path
  segment (a bare domain, e.g. `https://myapp.com`), derive `module` from the
  domain instead — strip `www.` and the TLD (e.g. `myapp.com` → `myapp`).
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
| Empty / very short response with no spec content | Ambiguous | Show the response excerpt, ask: "WebFetch returned <X>. Try MCP? (yes / no — paste content manually)" Wait for the reply. `yes` → go to **0.2 MCP fallback**. `no` → wait for the user to paste content directly, then treat the pasted text as the fetched content and continue to **0.3 Extract**. |
| Network error / DNS fail / timeout | Unreachable | Surface the error verbatim, ask the user to verify the URL. Wait for the reply. If the user provides a corrected URL, retry **0.1** with it. If the user says to stop, stop with "Cancelled — no spec written." |

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
  Wait for the reply. `use pasted content` → treat the pasted text as the
  fetched content, continue to **0.3 Extract**. `retry` (after making the
  page public) → re-run **0.1**. `retry` (after installing an MCP server) →
  re-run **0.2a**.

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
Wait for the reply.
- `yes` → Step 1
- `edit` → incorporate corrections, show the summary again
- `re-fetch` → wait for the user to update the source and reply "done", re-run 0.2

### 0.4 — Compute content hash

The fetched content is untrusted external input and may contain shell
metacharacters — never interpolate it into an inline shell command. Write it
to a temp file (e.g. `.spec-fetch-tmp.txt`) using the Write tool first, then
hash the file:

```bash
sha256sum <path-to-file> | awk '{print $1}'
```
Store this hash — it goes into the spec's `Source` metadata block in Step 2
and is compared again in Step 4 on future updates.

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

## Step 3 — Validate the spec

Score against these 5 dimensions (pass=1/fail=0 each):

| Dimension | Passes when |
|---|---|
| Completeness | Every stated user goal has at least one AC; no obvious gap between the description and the scenarios |
| Clarity | Each AC is unambiguous — a different reader would write the same scenario from it |
| Testability | Each AC has a concrete, observable Given/When/Then — not a vague goal statement |
| Independence | Scenarios don't depend on execution order or hidden shared state |
| Traceability | The underlying requirement or scenario traces to something the user said or the source doc contained — concrete copy/labels/values invented to make an AC testable are fine, but a fabricated requirement or scenario with no basis in the source is not |

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
Wait for the reply.
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

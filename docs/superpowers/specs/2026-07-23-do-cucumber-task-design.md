# Design: `/do-cucumber-task` (Sub-project 1 of 5) — CucumberStudio scenario → grounded `.feature` file

**Date:** 2026-07-23
**Status:** Approved, not yet implemented.
**Packaging:** One command file — `commands/do-cucumber-task.md` (prose-driven,
no companion script — same rationale as `/init`/`/spec`/`/scan-source`: this
requires LLM judgment throughout, reading a fetched scenario, verifying
wording against live/scanned selector sources, and writing Gherkin).

## Summary

`/do-cucumber-task <cucumberstudio-url>` fetches one CucumberStudio scenario
(e.g. `https://studio.cucumberstudio.com/projects/341786/test-plan/folders/4253324/scenarios/8115537`),
grounds it against this workspace's existing knowledge (a `/spec` spec.md
and/or `/scan-source` scanned docs), verifies its wording against real
selectors when a source is available, writes/updates
`specs/NNN-<module>/spec.md`, and generates `features/<module>.feature`.

## Why this is Sub-project 1 of 5, not the whole pipeline

The user's full ask — fetch a CucumberStudio scenario and end up with a
**runnable** automated test — requires four more pieces this plugin doesn't
have yet: a page-object/locator generator ("PomGenerator"), a step-definition
generator ("StepsGenerator"), a test runner, and finally wiring all of it
together. Building all five in one pass was explicitly considered and
rejected in favor of incremental delivery — the same choice already made
for `/spec` (deferred Step 4B/FeatureGenerator) and reaffirmed here:

| # | Sub-project | Status |
|---|---|---|
| **1 (this spec)** | `/do-cucumber-task` — fetch → ground → spec.md → `.feature` file | Building now |
| 2 | PomGenerator-equivalent — real page object + locator files | Future, own spec/plan cycle |
| 3 | StepsGenerator-equivalent — step definitions wiring Gherkin to page objects | Future, own spec/plan cycle |
| 4 | TestRunner-equivalent — actually runs the generated test, reports pass/fail | Future, own spec/plan cycle |
| 5 | Wire 1-4 into one end-to-end `/do-cucumber-task` flow | Future, after 2-4 exist |

This spec covers **Sub-project 1 only**. Later sub-projects are out of scope
here and will get their own spec/plan when picked up.

## Decisions (from brainstorm, with rationale)

| # | Decision | Rationale |
|---|---|---|
| Command name | `/do-cucumber-task` (top-level, no namespace) | User's exact naming; matches this plugin's flat convention |
| Selector's role in this sub-project | **Verification only** — confirm quoted labels/text in the Gherkin match real UI, never embed raw selectors in the `.feature` file | Matches the established Gherkin convention already documented from the reference framework ("No selectors, IDs, CSS classes... in any step") — raw selectors belong in Sub-project 2's locator files, not here |
| Platform detection | Infer from `.claude/docs/{backend,frontend,mobile}/` (which folder(s) exist); ask the user directly only when ambiguous (multiple types scanned, or none scanned at all) | Reuses `/scan-source`'s output instead of re-asking what's already known; falls back to asking (never guesses) exactly like every other command in this plugin |
| Selector source (when scanned docs exist for the determined platform) | **Always ask** which to use — the scanned docs (`components.md`/`screens.md`) or a live inspection (Playwright MCP for web / Appium MCP for mobile) | User's explicit call — no default preference, always confirm |
| When to ask for a live URL | **Only** when (a) no scanned source exists at all, or (b) the determined/confirmed platform is web/frontend. **Never** ask for a URL when the platform is backend (no UI, no selectors relevant) or mobile (mobile asks for an Appium app connection instead, never a URL) | User's explicit correction — URL is specifically a web-selector-acquisition input, not a generic "give me more info" prompt |
| Precondition to proceed | **Not a hard upfront filesystem check.** Resolved progressively: proceed if a spec.md exists, or scanned source exists for the determined platform, or (web only) the user can supply a live URL when asked. Block only when truly nothing is available — no spec, no scanned source, and (web) no URL to offer or (mobile) no app connection possible | User's explicit correction — a live URL offered in the moment is just as valid a grounding source as a pre-existing scan; the command shouldn't refuse to even ask |
| spec.md handling | **Always** write or update `specs/NNN-<module>/spec.md`, reusing `/spec`'s Step 2 write-spec template and Step 3 validation rubric, with a `Source` metadata block pointing at the CucumberStudio URL | User's explicit call — keeps the "spec is the durable source of truth" discipline established throughout this plugin; the CucumberStudio scenario becomes the spec's grounding input the same way a Notion/Confluence/Jira doc does in `/spec`'s Step 0 |
| CucumberStudio MCP tool discovery | `ToolSearch`, generic — never hardcode a specific tool name | Matches `/spec`'s Step 0.2 pattern for Notion/Confluence/Jira MCP discovery; we don't have first-hand documentation of `cucumberstudio-mcp`'s exact tool names, only its general purpose from the `/add-mcp` catalog entry |
| Missing MCP servers | If `cucumberstudio` (required) or `playwright`/`appium` (only if live inspection is chosen) aren't configured, tell the user to run `/add-mcp <name>` first | Reuses the catalog this plugin already built; consistent with how `/spec`'s Step 0.2a handles a missing MCP server |
| No raw selectors in `.feature` | Quoted UI text (button labels, headings, messages) is fine — verified against a real source — but CSS/XPath/testid strings never appear in Gherkin step text | Matches the reference framework's established Gherkin convention, already documented earlier in this plugin's design history |
| Does this sub-project run the test? | **No.** Generates spec.md + `.feature` only. Running is Sub-project 4's job | Keeps this sub-project's scope matched to what currently exists (no StepsGenerator output to run yet) |

## Scope

**In scope:**
- Parse a CucumberStudio scenario URL (`projects/<id>/test-plan/folders/<id>/scenarios/<id>`).
- Fetch the scenario via the `cucumberstudio` MCP (`ToolSearch`-discovered).
- Determine the module name (from the scenario/folder title — confirmed with
  the user, never guessed) and the platform (web/mobile/backend — inferred
  from scanned docs, confirmed when ambiguous).
- Resolve a grounding source per the progressive precondition logic above
  (spec.md / scanned docs / live URL for web / live Appium connection for
  mobile / backend needs no UI source).
- Verify the scenario's step wording against the resolved selector source
  when one exists; if genuinely none exists, still produce the `.feature`
  file but mark it `# unverified — no selector source available` rather
  than blocking.
- Write/update `specs/NNN-<module>/spec.md` (reusing `/spec`'s template +
  rubric + `Source` metadata block, pointed at the CucumberStudio URL).
- Generate `features/<module>.feature` (reusing the established Gherkin
  conventions: AC comment + Scenario, quoted-and-verified labels, a
  `# spec: specs/NNN-module/spec.md` traceability comment, no raw
  selectors).
- Final report: spec path, feature path, verification status per scenario
  step.

**Out of scope (this sub-project):**
- Page objects / locator files (Sub-project 2).
- Step definitions (Sub-project 3).
- Actually running the generated test (Sub-project 4).
- Fetching more than one scenario per invocation, or a whole folder's worth
  of scenarios (the URL pattern targets exactly one scenario).
- Any pipeline-agent concept (`Planner`, `Analyzer`, `FeatureGenerator` as
  named agents) — this command is self-contained prose, not a dispatcher.

## Components

| File | Purpose |
|---|---|
| `commands/do-cucumber-task.md` | The entire sub-project — URL parsing, CucumberStudio fetch, module/platform resolution, grounding-source resolution, selector verification, spec.md write (reusing `/spec`'s template inline — not a cross-command invocation, consistent with this plugin's no-skill-extraction-yet convention), `.feature` generation, report. |

## Data flow

```
/do-cucumber-task <cucumberstudio-url>
  1. Parse the URL: extract projectId, folderId, scenarioId.
     Malformed URL (doesn't match the expected pattern) → error, stop.

  2. Resolve the `cucumberstudio` MCP tool via ToolSearch.
     Not found → tell the user to run `/add-mcp cucumberstudio` first, stop.

  3. Fetch the scenario (title, steps, folder/project names) via the
     resolved tool.

  4. Determine `module`:
       Derive a candidate from the scenario/folder title.
       Ask the user to confirm or correct it. Wait for the reply.

  5. Determine platform:
       ls .claude/docs/ 2>/dev/null
       - Exactly one of {backend, frontend, mobile} present → use it.
       - More than one present → ask which this scenario is for.
       - None present → ask directly: backend / frontend / mobile?
       Wait for the reply in the ambiguous/none cases.

  6. Resolve the grounding/selector source, branching on platform:
       backend  → use spec.md / .claude/docs/backend/ content directly for
                  business-logic grounding; no selector step at all.
       mobile   → .claude/docs/mobile/screens.md exists → ask: use that, or
                  a live Appium connection? Wait for reply.
                  Doesn't exist → ask for a live Appium app connection.
                  Neither available → proceed with the scenario UNVERIFIED
                  (mark the .feature file accordingly), do not block.
       web      → .claude/docs/frontend/components.md exists → ask: use
                  that, or a live URL? Wait for reply.
                  Doesn't exist → ask directly for a live URL. Given →
                  continue using it. Not given → proceed with the scenario
                  UNVERIFIED (mark the .feature file accordingly), do not
                  block.

  7. If a selector source was resolved (scanned docs, live Playwright
     navigation, or live Appium connection): for each scenario step
     mentioning UI text (button labels, headings, messages), verify the
     exact wording against that source. Note any mismatch found — use the
     REAL wording in the generated feature, not the possibly-stale
     CucumberStudio wording, and flag the discrepancy in the report.

  8. Write/update specs/<NNN>-<module>/spec.md:
       - Determine NNN the same way /spec does (next after highest
         existing, or update in place if a spec for this module already
         exists).
       - Populate using /spec's Step 2 template (Status, Platform, Target,
         Description, User Stories/ACs derived from the CucumberStudio
         scenario's steps).
       - Append the Source metadata block: Source = "CucumberStudio",
         Source URL = the given link, Source Last Synced = now.
       - Run /spec's Step 3 5-dimension rubric; fix inline if <5/5 (do not
         loop back to a brainstorm step here — this command's input is
         already a structured scenario, not free-text needing brainstorm).

  9. Generate features/<module>.feature:
       - Feature line from the scenario's feature/folder title.
       - One Scenario block per CucumberStudio scenario step group,
         quoted UI text as verified in step 7 (or original CucumberStudio
         wording, explicitly marked unverified, if step 7 found no source).
       - `# spec: specs/NNN-module/spec.md` traceability comment.
       - `# unverified — no selector source available` header note when
         step 6 resolved to "no source, proceeding anyway."

  10. Report: spec.md path, feature file path, platform, selector source
      used (or "unverified"), any wording discrepancies found and
      corrected, and a reminder that page objects/step definitions/test
      execution are not part of this command yet.
```

## Error / edge handling

| Situation | Behavior |
|---|---|
| Malformed CucumberStudio URL | Error naming the expected pattern, stop |
| `cucumberstudio` MCP not installed | Tell the user to run `/add-mcp cucumberstudio`, stop |
| CucumberStudio auth wall / fetch failure | Surface the real error, ask the user to check credentials or paste the scenario content directly (mirrors `/spec`'s Step 0.2 exhaustion path) |
| Scenario has no steps / empty content | Report this, ask the user to confirm the URL is correct, stop rather than inventing steps |
| Ambiguous platform (multiple `.claude/docs/` subfolders) | Ask which one this scenario targets — never guess |
| No platform signal at all (`.claude/docs/` empty/missing) AND no spec.md exists for any module | Ask the user directly: backend / frontend / mobile? Then proceed per that platform's branch in step 6 |
| Web, no scanned frontend docs, user has no URL to give | Proceed unverified — write the `.feature` with the "unverified" marker, do not block |
| Mobile, no scanned mobile docs, user can't connect an app | Same — proceed unverified, do not block |
| Backend platform | Never asks for a URL or app connection — backend has no UI to verify against |
| A step's quoted text doesn't match the real UI (verified case) | Use the real wording in the `.feature`, flag the discrepancy explicitly in the final report — never silently keep the wrong CucumberStudio wording |
| Existing spec.md for this module scores <5/5 on the rubric after this update | Fix inline (this command has structured input already, unlike `/spec`'s free-text brainstorm case) and re-score once |

## Follow-ups (not this spec)

Sub-projects 2-5 from the table above — each gets its own spec/plan when
picked up, per the user's confirmed order.

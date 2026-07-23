# Design: `/spec` — spec-first authoring command

**Date:** 2026-07-23
**Status:** Approved, not yet implemented.
**Packaging:** One command file — `commands/spec.md` (prose-driven, no companion
script — same rationale as `/init`: this requires LLM judgment throughout,
reading source docs, brainstorming, scoring a rubric).

## Summary

`/spec <url-or-app-id | notion-url | confluence-url> [screen] [description]`
creates, updates, or validates a module spec at `specs/NNN-<module>/spec.md`
**before** any test-generation pipeline runs. This is a right-sized adaptation
of `qa-automation-framework`'s `commands/qa/spec.md` for `lian-qa-plugin`'s
current state (no Planner/Analyzer/FeatureGenerator exist yet).

## Why this is scoped down from the reference

The reference `/qa:spec` (344 lines) is deeply coupled to machinery that
doesn't exist in this plugin yet:

- The `speckit-specify` and `qa-spec-writing` skills (methodology extracted to
  portable skill files) — no other command/agent in this plugin needs that
  methodology yet, so extracting it now would be a premature abstraction.
- Step 4B (feature-file drift reconciliation) reads `src/features/<module>.feature`
  — produced by `FeatureGenerator`, which doesn't exist here.
- The "after spec is finalized" pointer to `/qa:web` / `/qa:native` — neither
  command exists in this plugin.

Decided (with the user, after also considering and rejecting "build
Planner + Analyzer + FeatureGenerator first" as too large for this pass):
`/spec` ships now with its methodology inline and Step 4B omitted. A future
phase (own brainstorm/spec/plan cycle) builds `FeatureGenerator` — at that
point `/spec` gains Step 4B back, and the validation rubric can be extracted
to a skill if a second consumer actually needs it.

## Decisions (from brainstorm, with rationale)

| # | Decision | Rationale |
|---|---|---|
| Command name | `/spec` (top-level, no namespace) | Matches this plugin's established convention (`/rename`, `/add-mcp`, `/init`) |
| Source fetching (Step 0) | **Included** — WebFetch first, MCP fallback via `ToolSearch`, generic (no hardcoded tool names) | User wants real support for pulling ACs from Notion/Confluence/Jira, not just manual descriptions. Self-contained — doesn't depend on any unbuilt phase |
| Drift reconciliation (Step 4) | **4A only** (source-content-hash drift) — **4B omitted** (feature-file drift) | 4A is self-contained; 4B needs `FeatureGenerator`'s output, which doesn't exist. Revisit when `FeatureGenerator` ships |
| Methodology location | **Inline in `commands/spec.md`**, not a separate skill | No second consumer exists yet (YAGNI) — extract to a `qa-spec-writing` skill only when `FeatureGenerator` or another command actually needs to read the same rubric/checklist |
| "After spec is finalized" pointer | Removed the `/qa:web` / `/qa:native` suggestion (neither exists); replaced with a note that the test-generation pipeline is a future phase | Don't reference commands that don't exist |
| Spec numbering / location | `specs/NNN-<module>/spec.md`, same as the reference | Already has scaffolding: `/init new`'s A5 step already creates an empty `specs/` directory in the workspace |
| FeatureGenerator / Planner / Analyzer | **Explicitly out of scope for this spec** | Confirmed with the user: ship `/spec` alone this session; the trio is a separate, later multi-session effort |

## Scope

**In scope:**
- Argument parsing: source platform detection (Notion/Confluence/Jira URL vs.
  web target URL vs. mobile app id), module-name derivation.
- Existing-spec detection (`ls specs/*-<module>/`) to route new vs. evolve.
- Step 0: WebFetch-first source fetch, MCP fallback (generic `ToolSearch`,
  auth-wall handling, AC extraction heuristics), content-hash computation.
- Step 1: brainstorm dialogue (max 5 questions), skipped when ACs are already
  clear.
- Step 2: write `specs/NNN-<module>/spec.md` (module number, Given/When/Then
  ACs, `Source` metadata block when a source was used).
- Step 3: 5-dimension validation rubric (Completeness, Clarity, Testability,
  Independence, Traceability), inline scoring logic.
- Step 4 (Evolve): **4A only** — source drift detection via content hash,
  reconciliation prompt, spec update.
- Final summary + display-only (never executed) suggested git commands.

**Out of scope (deferred):**
- Step 4B (feature-file drift reconciliation) — needs `FeatureGenerator`.
- `speckit-specify` / `qa-spec-writing` skill extraction — no second consumer
  yet.
- `Planner`, `Analyzer`, `FeatureGenerator`, `PomGenerator`, `StepsGenerator`,
  `TestRunner`, `SelectorHealer`, `QualityGatekeeper` — all future phases,
  each gets its own brainstorm/spec/plan cycle.
- Any pointer to `/qa:web` / `/qa:native` or equivalents — they don't exist.
- Auth-flow-aware spec content — no auth phase exists yet in this plugin.

## Components

| File | Purpose |
|---|---|
| `commands/spec.md` | The entire feature — argument parsing, source fetch (Step 0), brainstorm (Step 1), spec writing (Step 2), validation (Step 3), source-drift evolve (Step 4A), final report. All inline, no companion script or skill. |

## Data flow

```
/spec <url-or-app-id | notion-url | confluence-url> [screen] [description]
  1. Detect source platform (Notion/Confluence/Jira) vs. target
     (web URL / mobile app id) from the argument shape.
  2. Derive `module` (from target URL path segment, screen name, or
     source page title).
  3. ls specs/*-<module>/ :
       found     → read existing spec; if it has a Source metadata block,
                   go to Step 4 (Evolve, 4A only); else go to Step 1.
       not found → determine next NNN via `ls specs/ | sort | tail -1` + 1;
                   if a source URL was given → Step 0; else → Step 1.
  4. Step 0 (only if a source URL was given):
       0.1 WebFetch the URL directly (always tried first, any platform).
       0.2 If auth-walled → ToolSearch for a platform MCP tool (generic,
           no hardcoded tool names) → authenticate if needed → fetch via MCP.
           If no MCP server is available for the platform → ask the user to
           paste content, make the page public, or install an MCP server
           (mention /add-mcp jira covers Confluence+Jira via mcp-atlassian).
       0.3 Extract ACs/user-stories/edge-cases/out-of-scope from the raw
           content (heading/list/table pattern matching). Show the extraction
           summary, ask the user to confirm/edit/re-fetch.
       0.4 Compute sha256 of the raw source content — store for Step 2's
           Source metadata block and Step 4A's later drift check.
  5. Step 1 (brainstorm) — skipped if Step 0 produced clear ACs with no
     "unclear items", or the user supplied 3+ explicit ACs. Otherwise ask up
     to 5 focused questions (primary goal, success/failure paths, edge cases,
     validation/conditional UI, out-of-scope).
  6. Step 2 — write specs/<NNN>-<module>/spec.md: module, platform, target
     URL/app, description, Given/When/Then ACs; append the Source metadata
     block (Source / Source Last Synced / Source Content Hash) only if a
     source was used. Show the spec summary table.
  7. Step 3 — score the 5-dimension rubric: 5/5 → ready; 3-4/5 → show failed
     dimensions with quoted examples, fix inline; <3/5 → back to Step 1.
  8. Step 4 (Evolve, entered only when updating an existing spec with a
     Source block) — 4A only: re-fetch via Step 0.1-0.2, recompute hash,
     compare to stored hash. Match → "Source unchanged since <date>", done.
     Differ → show added/removed/modified ACs, ask to update (yes/no/
     selective), apply, re-hash, re-validate (back to Step 3).
  9. Final report: spec path, scenario table, a note that the
     test-generation pipeline is a future phase (no /qa:web-equivalent
     exists yet), and a **display-only** suggested `git add`/`git commit`
     block (never executed by the command itself).
```

## Validation rubric (Step 3, inline — not a separate skill)

Score each dimension 0/1 (pass/fail), same taxonomy as the reference:

| Dimension | Passes when |
|---|---|
| Completeness | Every stated user goal has at least one AC; no obvious gap between description and scenarios |
| Clarity | Each AC is unambiguous — a different reader would write the same scenario |
| Testability | Each AC has a concrete, observable Given/When/Then — not a vague goal statement |
| Independence | Scenarios don't depend on execution order or hidden shared state |
| Traceability | Every AC in the spec traces to something the user said or the source doc contained — nothing invented |

5/5 → spec is ready. 3-4/5 → show the failing dimension(s) with a quoted
example from the spec, fix now, re-score. <3/5 → the spec needs more input;
re-enter Step 1's brainstorm.

## Error / edge handling

| Situation | Behavior |
|---|---|
| WebFetch returns login-page/redirect/401/403 signals | Auth-walled → Step 0.2 MCP fallback |
| WebFetch returns empty/very short content | Ambiguous → show the excerpt, ask user: try MCP / paste content manually |
| WebFetch network error/timeout | Surface the error verbatim, ask user to verify the URL |
| Platform has no MCP server installed at all | Offer: paste content directly / make page public + retry / install an MCP server (point at `/add-mcp`) + retry |
| Step 0.3 extraction has "unclear items" | Do not skip Step 1 — brainstorm covers the unclear items specifically |
| User disagrees with the extraction summary | `edit` → incorporate corrections, re-show summary; `re-fetch` → wait for "done", re-run Step 0.2 |
| Existing spec has no `Source` metadata block | Treat as a manually-authored spec — Step 4 (Evolve) doesn't apply; any update goes through Step 1→3 again |
| Rubric score <3/5 twice in a row | Still loop back to Step 1 — never ship a spec below 3/5 silently |
| MCP fetch returns secrets/PII (API keys, internal URLs, personal data) | Redact before writing into the spec |

## Follow-ups (not this spec)

- Step 4B (feature-file drift) — added back once `FeatureGenerator` exists.
- `qa-spec-writing` skill extraction — once a second consumer needs the same
  methodology.
- `Planner` / `Analyzer` / `FeatureGenerator` and the rest of the pipeline —
  each its own future brainstorm/spec/plan cycle.

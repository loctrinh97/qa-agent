# Design: `/init` — Phase 1 of the QA automation pipeline

**Date:** 2026-07-22
**Status:** Approved, not yet implemented.
**Packaging:** One command file — `commands/init.md` (prompt-driven, no scripts —
see "Why no scripts" below).

## Summary

`lian-qa-plugin` is pivoting to become a personal QA automation plugin (same
domain as `qa-automation-framework`, not a generic command grab-bag as
originally scoped). `/init` is the entry point, with two modes:

- **`/init new [--no-install]`** — scaffold a fresh Playwright + BDD test
  workspace (MVP: no auth flow yet). `--no-install` skips the final
  `npm install`.
- **`/init existing`** — scan an existing project's codebase and generate a
  `.claude/` knowledge base (`CLAUDE.md` + 10 docs files) grounded 100% in the
  actual code.

No argument → ask which mode (new / existing) rather than guessing.

## Why this is "Phase 1", not the whole framework

The reference project (`qa-automation-framework`, in the sibling
`claudecode-qa-automation-main/` checkout) has a full pipeline: `Planner` →
`Analyzer` → `FeatureGenerator`/`PomGenerator` → `StepsGenerator` →
`TestRunner` → `SelectorHealer` → `QualityGatekeeper`, plus a `QA_ROOT`
workspace resolver used by every command, plus a 3-flow auth system
(A/B/C, with MFA models: none/push/TOTP/SMS/FIDO/SSO). Its own `/qa:init`
command (~1500 lines) scaffolds against all of that.

None of that exists yet in `lian-qa-plugin`. Copying `/qa:init` verbatim would
produce a command that references agents, scripts, and a resolver contract
that don't exist here — broken on first run. Decided (with the user) to build
this in phases, each with its own spec:

| Phase | Scope |
|---|---|
| **1 (this spec)** | `/init new` (MVP, no auth) + `/init existing` (knowledge scan) |
| 2 | Workspace resolver (`QA_ROOT`-equivalent) + `Planner` agent |
| 3 | `Analyzer` + `FeatureGenerator` + `PomGenerator` |
| 4 | `StepsGenerator` + `TestRunner` |
| 5 | `SelectorHealer` + `QualityGatekeeper` |
| 6 | Full auth flow (A/B/C, MFA) — upgrades `/init new`'s questionnaire |

This spec covers **Phase 1 only**. Later phases are out of scope here and will
get their own spec/plan when picked up.

## Decisions (from brainstorm, with rationale)

| # | Decision | Rationale |
|---|---|---|
| Plugin direction | `lian-qa-plugin` is now QA-automation-focused (reversing the earlier "not QA-related" scoping) | User's explicit call — `/init new` should mirror `qa-automation-framework`'s `/qa:init` in spirit |
| Command name | `/init`, with `new` / `existing` as the first argument | User preference — explicit argument over auto-detection, to avoid misdetecting an ambiguous directory |
| `/init new` scope | MVP: directory scaffold + `package.json` + `playwright.config.ts` + `tsconfig.json` + `.gitignore` + `BasePage.ts` + `npm install`. **No auth questionnaire, no `QA_ROOT` migrate-artifacts logic, no `AUTH_ROLE`/`storageState`.** | Auth flow and multi-agent pipeline don't exist yet — scaffolding for them now would reference nothing |
| Workspace model | Keep a workspace concept from day one: ask a name, create `~/.claude-lian-qa/<name>/`, write `~/.claude-lian-qa/.active` | Cheap to add now; Phase 2's resolver can reuse the `.active` pointer instead of a breaking migration later. Deliberately simpler than `QA_ROOT`: no multi-session lock, no migrate-from-cache logic (nothing to migrate yet) |
| Platform question | Ask web / mobile / both even in the MVP (drop only the auth sub-questions) | Branches `package.json` dependencies correctly from the start; cheap, self-contained, doesn't depend on anything unbuilt |
| `/init existing` | Implement (near-)verbatim per the user's supplied prompt: scan → `.claude/CLAUDE.md` + `.claude/docs/*.md` (10 files), grounded 100% in actual code, "not determined" instead of guessing | Self-contained — doesn't depend on any later phase. User provided the exact content spec already |
| Scripting | **No `scripts/*.sh` extraction for either mode** | Unlike `/rename` and `/add-mcp` (deterministic string/JSON edits), both modes here require LLM judgment: asking questions, reading/understanding code, synthesizing docs. There is no deterministic script to extract — keeping the logic in the command's prose is correct, not a shortcut |

## Scope

**In scope:**
- `/init new` — MVP scaffold as decided above, with the web/mobile/both
  platform question.
- `/init existing` — codebase scan → `.claude/` knowledge base, per the
  user-supplied prompt.
- Both modes: confirm before writing/scaffolding; no automated git commit
  (matches the convention already established for `/rename` and `/add-mcp`
  in this plugin).

**Out of scope (deferred to later phases, not this spec):**
- Auth questionnaire (Q1–Q3), MFA models, Flow A/B/C, `auth/storageState*`,
  `scripts/save-auth.ts` / `programmatic-login.ts` / `refresh-auth.ts`.
- Multi-session workspace locking, migrate-artifacts-from-cache logic.
- Any agent (`Planner`, `Analyzer`, `FeatureGenerator`, etc.) or the
  `QA_ROOT`-style resolver other commands would depend on — those commands
  don't exist yet either.
- Mobile-specific scaffolding beyond adding the right `package.json`
  dependencies (no WDIO config file, no Appium capability files yet — that's
  Phase 2+ territory once there's an agent pipeline to drive it).

## Components

| File | Purpose |
|---|---|
| `commands/init.md` | Both modes. Routes on `$ARGUMENTS` (`new` / `existing` / missing → ask). Prompt-driven throughout — no companion script (see rationale above). |

## Mode A — `/init new` data flow

```
/init new
  1. Ask workspace name (suggest: basename of cwd). Wait for reply.
     Sanitize to [a-z0-9-].
  2. WORKSPACE="$HOME/.claude-lian-qa/<name>"
     mkdir -p "$WORKSPACE"
     echo "$WORKSPACE" > "$HOME/.claude-lian-qa/.active"
  3. Ask platform: web (w) / mobile (m) / both (b). Wait for reply.
  4. Show scaffold plan (files to be created, dependencies per platform
     choice) and ask to confirm (y/n). Abort on "n" — nothing created.
  5. On confirm, cd into $WORKSPACE and create:
       features/ pages/ locators/ step-definitions/ specs/ auth/   (dirs only)
       package.json          (Playwright + playwright-bdd + allure-playwright;
                                + WDIO/Appium deps if platform includes mobile)
       playwright.config.ts  (TEST_MODULE scoping; no AUTH_ROLE/storageState)
       tsconfig.json
       .gitignore
       pages/BasePage.ts     (minimal base class)
       qa-run-log.tsv         (empty, header row only)
  6. Run `npm install` unless `--no-install` was passed.
  7. Report: workspace path, files created, platform chosen, and remind
     no git command was run.
```

## Mode B — `/init existing` data flow

```
/init existing
  1. If .claude/ already exists at project root, ask: overwrite / merge
     (fill in only missing files) / abort. Abort → stop, nothing touched.
  2. Scan the codebase: folder structure, framework, config files,
     dependencies (package.json/requirements/etc.), existing test examples,
     CI config if present.
  3. Write .claude/CLAUDE.md — framework/language overview, project purpose,
     test commands (run all / run single / run by tag), required env vars,
     setup instructions.
  4. Write .claude/docs/*.md (10 files):
       architecture.md, structure.md, patterns.md, coding-conventions.md,
       test-strategy.md, test-case-template.md, selectors-locators.md,
       test-data.md, ci-cd.md, known-issues.md
     Every claim grounded in actual repo content. Anything not determinable
     from the code → literal text "not determined". Never guess.
  5. Report: list every file created, 1-2 line summary each.
```

## Error / edge handling

| Situation | Behavior |
|---|---|
| `/init` with no argument | Ask which mode (new / existing) — don't guess |
| `/init new`, workspace name already exists at `~/.claude-lian-qa/<name>/` | Show what's already there (like the existing-file check in `qa:init`'s skip-mode); ask reuse / pick a different name / abort |
| `/init new`, user declines the scaffold-plan confirmation | Abort, nothing created |
| `/init existing`, `.claude/` already exists | Ask overwrite / merge / abort (per data flow above) |
| `/init existing`, some aspect of the codebase can't be determined | Write the literal string "not determined" in that doc section — never guess |
| `/init existing`, project has no test examples at all | `test-case-template.md` and `patterns.md` explicitly say "not determined — no existing test examples found" rather than inventing a template |

## Follow-ups (not this spec)

Phases 2–6 from the table above — each gets its own spec when picked up.

# Design: `/do-cucumber-task` Sub-project 2 — Page Object / Screen Object / API Client generation

**Date:** 2026-07-24
**Status:** Approved, not yet implemented.
**Packaging:** No new command file. New steps appended directly into the
existing `commands/do-cucumber-task.md`, inserted between "Generate the
feature file" and "Report" (per user's explicit choice — sub-projects 2 and
5 from the original 5-sub-project table are merged: rather than building a
standalone command now and wiring it in later, generation logic grows
directly inside `do-cucumber-task.md` this round, and later rounds
(StepsGenerator, TestRunner) will do the same).

## Summary

Once `/do-cucumber-task` produces `features/<module>.feature` (Sub-project 1,
already shipped), it now goes on to generate the real, runnable-eventually
building block underneath that feature file:

| Platform | Artifact ("page object" equivalent) | Locator/endpoint equivalent |
|---|---|---|
| `frontend` (web) | `pages/<Module>Page.ts` extends `pages/BasePage.ts` | `locators/<module>.locators.ts` → `get<Module>Locators(page)` |
| `mobile` | `pages/mobile/<Module>Screen.ts` | `locators/mobile/<module>.locators.ts` → `get<Module>Locators()` (no `page` arg) |
| `backend` | `api-clients/<Module>Client.ts` wrapping Playwright `APIRequestContext` | none — HTTP method/path is inline in the client, since it's a contract, not fragile UI state |

Step definitions and test execution are still out of scope — those are
Sub-projects 3 and 4.

## Why this shape (decisions from brainstorm)

| # | Decision | Rationale |
|---|---|---|
| Reuse vs. design from scratch | **Adapt the conventions already proven in the sibling reference plugin** `claudecode-qa-automation-main/agents/{pom-generator,steps-generator,test-runner}.md` | Those conventions (`BasePage`, `playwright-bdd` `createBdd()`, `@wdio/cucumber-framework` for mobile, selector-priority order) already match exactly what `lian-qa-plugin`'s `/init new` scaffolds (`pages/BasePage.ts`, `@playwright/test`, `playwright-bdd`, and the mobile devDependency block). No reason to re-derive from zero. |
| Backend scope | **Included in this round**, not deferred | User's explicit call. No existing `/init new` platform option scaffolds a backend workspace, but... |
| Backend HTTP stack | **Reuse `@playwright/test`'s `APIRequestContext`** (the `request` fixture) — no new dependency | `/init new`'s web scaffold already installs `@playwright/test`, which supports headless API testing via `request` with zero extra packages. Confirmed by user over a separate/other HTTP client. |
| Mobile stack | WebdriverIO + Appium (unchanged) | Matches what `/init new`'s mobile platform option (`m`/`b`) already installs (`@wdio/cucumber-framework`, `webdriverio`, `@wdio/appium-service`, etc.) |
| Command shape | **Extend `do-cucumber-task.md` directly** — no new standalone command this round | User's explicit choice, overriding the original spec's "own spec/plan cycle per sub-project" framing. Sub-project 2's logic and sub-project 5's "wire it into the one flow" collapse into a single step here. |
| Workspace model | **No `QA_ROOT` resolution.** Everything is read/written relative to the current working directory, exactly like `/do-cucumber-task`, `/scan-source`, `/spec`, and `/init new` already do. | `lian-qa-plugin` has never used the reference plugin's `~/.claude-qa/<app>/` workspace-resolution concept — `/init new` scaffolds `pages/`, `locators/`, etc. directly under cwd, and every existing command already assumes cwd is that project root. Importing `QA_ROOT` resolution now would be an unrequested, inconsistent addition. |
| Selector/endpoint source | **Reuse whatever `do-cucumber-task` already resolved and verified earlier in the same run** (scanned docs content, or the still-open live Playwright/Appium session/snapshot from the "Verify step wording" step) — never re-verify live from scratch, never ask the user again | User's explicit confirmation. Avoids a second round of live browser/Appium work for the same run, and matches the "ask once, don't re-ask" discipline already established across this plugin's commands. |
| Unverified case (`SELECTOR_SOURCE=none`) | Still generate the file, but with `// TODO: unverified — ...` stubs per element/endpoint instead of blocking | Matches Sub-project 1's existing "proceed, mark unverified, don't block" precedent — consistent behavior across the whole command. |
| Never guess a selector/endpoint | If no grounded source exists for a specific element/endpoint (even when the overall source is otherwise verified), stub it with a TODO rather than inventing a plausible-looking one | Matches the plugin-wide "never guess — ask or mark unverified" rule already stated in `/scan-source`, `/spec`, and Sub-project 1 of this same command. |
| Existing file for the same module | Read and merge (add new methods, keep existing ones) rather than overwrite wholesale | "Surgical changes" — matches `GUIDELINES.md`'s principle from the reference framework and this plugin's general no-unrequested-rewrite practice. |

## Scope

**In scope:**
- After `.feature` file generation, derive `Module` (PascalCase) from `MODULE`.
- Re-read (never re-fetch/re-verify) the grounding source resolved earlier in
  this same `do-cucumber-task` run.
- Scan existing `pages/`/`locators/`/`api-clients/` (per platform) for
  project style before writing, exactly like the reference `pom-generator`
  agent's Step 0.
- Generate the locator/endpoint file (frontend/mobile only).
- Generate the page object / screen object / API client file, with one
  method per relevant Gherkin step in the generated `.feature` file.
- Merge into an existing file for the same module rather than overwriting it.
- TODO-stub any element/endpoint that has no grounded source, instead of
  guessing or blocking.
- Extend the final report to include the new artifact paths and
  verified/stubbed counts.

**Out of scope (this round):**
- Step definitions (Sub-project 3).
- Running any test (Sub-project 4).
- A backend `/init new` platform option / scaffold — this design assumes
  `pages/`, `locators/`, `api-clients/` etc. can simply be created on first
  use even without a prior `/init new` backend flow; scaffolding a proper
  backend workspace preset is not part of this change.
- Re-verifying selectors/endpoints beyond what Sub-project 1 already
  resolved in the same run.
- Any live browser/Appium session re-opening.

## Components

| File | Change |
|---|---|
| `commands/do-cucumber-task.md` | New sections inserted after "Generate the feature file": module/class name derivation, source re-read, project-style scan, locator/endpoint file generation, page/screen/client file generation, updated Report section. **Also**: the existing "Rules" section currently states "Do NOT generate page objects, locators, or step definitions — those are future phases of this plugin." That line must be updated to reflect that page objects/locators/API clients ARE now generated here — only step definitions and test execution remain future phases. Leaving the old blanket statement in place would directly contradict the new behavior. |

## Data flow (new steps, inserted after "Generate the feature file")

```
10. Derive Module (PascalCase) from MODULE (e.g. user-login -> UserLogin).

11. Re-read the grounding source already resolved earlier in this run —
    never re-fetch, never re-open a live session, never ask the user again:
      frontend/mobile, scanned docs   -> read components.md / screens.md content
      frontend/mobile, live source    -> reuse the snapshot/session captured
                                          during "Verify step wording"
      backend                        -> read .claude/docs/backend/api-contracts.md
                                          or specs/*/spec.md
      SELECTOR_SOURCE=none            -> every element is "unverified"

12. Scan existing project style:
      frontend:  ls pages/*.ts locators/*.ts
      mobile:    ls pages/mobile/*.ts locators/mobile/*.ts
      backend:   ls api-clients/*.ts
    If a file for this module already exists, read it — this generation
    merges into it (Step 14/15), it does not overwrite it. If empty, use
    the default conventions from "Summary" above.

13. Generate the locator/endpoint file (frontend/mobile only; backend skips
    this — HTTP method/path stay inline in the client):
      frontend: locators/<module>.locators.ts, get<Module>Locators(page)
      mobile:   locators/mobile/<module>.locators.ts, get<Module>Locators()
    Each locator entry:
      - grounded (scanned docs or live) -> real selector, following this
        plugin's existing selector-priority order per platform
      - ungrounded -> `// TODO: unverified — <element description>`

14. Generate the page object / screen object / API client file:
      frontend: pages/<Module>Page.ts, extends BasePage, imports the locator
                factory. Methods represent semantic actions/assertions
                (e.g. `login(email, password)`, `expectLoginError(msg)`),
                grouping multiple Gherkin steps that describe one action
                into a single method — NOT a rigid 1:1 step-to-method
                mapping. Matches the reference pom-generator's example
                shape (goto/login/expectLoginSuccess/expectLoginError).
      mobile:   pages/mobile/<Module>Screen.ts, same shape/grouping rule,
                no `page` fixture, WebdriverIO $('~...') element access
      backend:  api-clients/<Module>Client.ts, wraps `request:
                APIRequestContext`, one async method per endpoint
                referenced by the feature's steps (an endpoint call is
                already a natural 1:1 unit, unlike UI actions), returns the
                parsed response
    If a file already exists for this module: add new methods for any new
    steps, leave existing methods untouched.

15. Write files (Write tool). No staging directory.
```

## Error / edge handling

| Situation | Behavior |
|---|---|
| A Gherkin step doesn't map to any identifiable element/endpoint | Generate a stub method with `// TODO: <reason>` — don't block the rest of generation |
| Page object / screen / client file already exists for this module | Read and merge — add new methods, keep existing ones untouched (no wholesale rewrite) |
| `backend` platform, `.claude/docs/backend/` empty AND `spec.md` has no concrete endpoint shape | Generate the whole client with TODO stubs, don't block, flag clearly in the report |
| The live Playwright/Appium session from Sub-project 1's verification step is no longer available (e.g. it timed out) | Do not open a new session — treat any element/endpoint that needed it as unverified, TODO-stub it |
| `SELECTOR_SOURCE=none` (Sub-project 1's existing "proceed unverified" path) | Every element/endpoint in this module is TODO-stubbed; report says "unverified" |

## Report (extends Sub-project 1's existing final report)

```
Spec: specs/<NNN>-<module>/spec.md
Feature: features/<module>.feature
Page object / Screen / API client: <path>
Locators: <path, or "not applicable (backend)">
Selectors/endpoints grounded: <n>/<total>
TODO stubs remaining: <n> (method names listed)

Not generated yet (future phases): step definitions, test execution.
```

## Follow-ups (not this spec)

- Sub-project 3 (StepsGenerator-equivalent) — generate step definitions
  wiring the `.feature` file to the page/screen/client methods generated
  here. Own brainstorm/design round, same "extend `do-cucumber-task.md`
  directly" approach.
- Sub-project 4 (TestRunner-equivalent) — actually run the generated test,
  report pass/fail.
- A backend `/init new` scaffold preset (out of scope here, noted as a gap).

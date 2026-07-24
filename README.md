# lian-qa-plugin

AI-driven QA automation plugin for Claude Code — a **spec-first** workflow
for writing autotests, whether a project already has specs/tests or not.

## Install

**From GitHub:**
```bash
/plugin marketplace add loctrinh97/qa-agent
/plugin install lian-qa-plugin@lian-plugins
```

**From a local checkout:**
```bash
/plugin marketplace add /path/to/lian-qa-plugin
/plugin install lian-qa-plugin@lian-plugins
```

## Recommended workflow

```
                 ┌─ project already has source code / docs? ──┐
                 │                                              │
          /init existing                                  /init new
     (scan current project,                        (scaffold a fresh
      generate .claude/ docs)                        test workspace)
                 │                                              │
                 └──────────────────┬───────────────────────────┘
                                     ▼
                    /scan-source <backend|frontend|mobile paths>
                 (scan the APP UNDER TEST's own source repos —
                  real endpoints, real UI test-ids, real business rules)
                                     ▼
                /spec <url>            or       /do-cucumber-task <url>
          (Notion/Confluence/Jira            (CucumberStudio scenario →
           doc → spec.md)                     spec.md + .feature file)
```

Both `/spec` and `/do-cucumber-task` write `specs/NNN-<module>/spec.md` —
grounded in whatever `/scan-source` already found, and verified against
real selectors when a source (scanned docs or a live URL/app) is available.

## Commands

| Command | What it does |
|---|---|
| `/init new [--no-install]` | Scaffold a fresh Playwright + BDD test workspace at `~/.claude-lian-qa/<name>/` — asks for a workspace name and platform (web/mobile/both), writes `package.json`, `playwright.config.ts`, `tsconfig.json`, `BasePage.ts`, and a governance `CLAUDE.md`. |
| `/init existing` | Scan the **current** project's own codebase (the test-tooling repo itself) and generate `.claude/CLAUDE.md` + 10 docs files (architecture, patterns, coding-conventions, selectors-locators, etc.) grounded 100% in real code. |
| `/scan-source <path1> [path2] ...` | Scan one or more **already-locally-cloned** application source repos (backend/frontend/mobile — auto-detected from real code signals, always confirmed with you). Writes `.claude/docs/{backend,frontend,mobile}/` — real API endpoints, real UI test-ids, real business rules. Cumulative across runs. Does **not** clone anything, and does not scan the test-tooling repo (that's `/init existing`'s job). |
| `/spec <url \| notion-url \| confluence-url \| jira-url> [screen] [description]` | Create, update, or validate a module spec at `specs/NNN-<module>/spec.md`. Tries `WebFetch` on a source link first, falls back to MCP only when auth-walled. Includes a brainstorm step, a 5-dimension validation rubric, and source-drift reconciliation on update. |
| `/do-cucumber-task <cucumberstudio-url>` | Fetch one CucumberStudio scenario, ground it against this workspace's `spec.md`/scanned-source knowledge, verify its wording against real selectors when available, write/update `specs/NNN-<module>/spec.md`, and generate `features/<module>.feature`. **Sub-project 1 of 5** — does not yet generate page objects, step definitions, or run the test (see Roadmap). |
| `/add-mcp [playwright\|github\|appium\|azure-devops\|jira\|cucumberstudio]` | Add an MCP server to this plugin's config from a curated, verified catalog. No arg → shows the list and asks which one. Never invents package names. |
| `/rename <new-name>` | Rename this plugin's id across `plugin.json`, `marketplace.json`, and `README.md`. Does not touch the marketplace's own name. |

Every command follows the same discipline: **never guess** — ask when
something is ambiguous, write "not determined" when evidence is absent, and
**never run git commands on your behalf** — you always review and commit
yourself.

## Prerequisites per command

- `/spec` (Notion/Confluence/Jira sources) and `/do-cucumber-task`
  (CucumberStudio): may need an MCP server. Run `/add-mcp cucumberstudio`,
  `/add-mcp jira` (covers Jira + Confluence), etc. first if prompted.
- `/do-cucumber-task` and `/spec`'s live-selector-verification path (when no
  scanned source exists yet): may need `/add-mcp playwright` (web) or
  `/add-mcp appium` (mobile) for live inspection — or just answer "no" to
  proceed without verification.
- `/scan-source` and `/init existing`: no MCP needed, pure local file
  reading — clone the target repo(s) yourself first.

## Roadmap

`/do-cucumber-task` is Sub-project 1 of a 5-part effort to go from "a
CucumberStudio scenario" to "a runnable automated test":

1. ✅ `/do-cucumber-task` — scenario → `spec.md` + `.feature` file
2. ⏳ Page object / locator generator
3. ⏳ Step definition generator
4. ⏳ Test runner
5. ⏳ Wire 1–4 into one end-to-end flow

## Structure

```
.claude-plugin/
  plugin.json        — plugin manifest
  marketplace.json    — single-plugin marketplace listing (enables install above)
commands/              — the 6 slash commands listed above
scripts/               — deterministic helper scripts (rename.sh, add-mcp.sh)
docs/superpowers/
  specs/               — design specs (one per command)
  plans/               — implementation plans (one per command)
```

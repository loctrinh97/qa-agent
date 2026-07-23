# Design: `/scan-source` — scan application source code for autotest context

**Date:** 2026-07-23
**Status:** Approved, not yet implemented.
**Packaging:** One command file — `commands/scan-source.md` (prose-driven, no
companion script — same rationale as `/init` and `/spec`: this requires LLM
judgment throughout, reading arbitrary code and classifying it).

## Summary

`/scan-source <path1> [path2] ...` scans one or more **already-locally-cloned**
application source repositories (backend / frontend / mobile — auto-detected,
not user-specified) and writes grounded reference docs to
`.claude/docs/{backend,frontend,mobile}/`, plus a cumulative `.claude/CLAUDE.md`
index. This serves the case the user described: a project has no spec, or its
spec is outdated, and the QA engineer needs to read the actual application
source (not test-tooling source) to find real locators/testids and real
business logic before writing tests.

## Why this is a new command, not a mode of `/init existing`

`/init existing` already does something close (scan a codebase → grounded
`.claude/docs/*.md`), but it has a different job: it documents **the current
project's own testing conventions** (patterns, coding-conventions, locators
*already established in this repo's test code*, CI, known issues) — a single
target, assumed to already be a test-tooling repo the user is sitting in.

`/scan-source` documents **a different repo's application source** (the app
under test's BE/FE/mobile code) to extract facts a test author needs — API
endpoints, business rules, UI component test-ids, screen names — across
**multiple** repos in one growing `.claude/` tree. Different purpose, different
output shape (`backend/`/`frontend`/`mobile/` subfolders vs. `docs/*.md` flat),
multiple targets vs. one. Confirmed with the user: keep `/init existing`
unchanged for its existing job; `/scan-source` is additive and separate.

## Decisions (from brainstorm, with rationale)

| # | Decision | Rationale |
|---|---|---|
| Command name | `/scan-source` (top-level, no namespace) | Matches this plugin's convention (`/rename`, `/add-mcp`, `/init`, `/spec`) |
| Cloning | **Not the command's job** — the user clones the target repo(s) themselves first, then passes the local path | User's explicit call. Keeps the command simple (pure local Read/Grep/Glob, like `/init existing`) and avoids credential/auth handling for git hosts entirely |
| Argument shape | **Positional paths, no `--backend`/`--frontend`/`--mobile` flags** — one or more local paths, type is auto-detected per path | User's explicit call, after initially designing flag-based input. Less typing, and the command already has to read the repo to scan it, so detecting type from the same read is nearly free |
| Detection confidence handling | **Always show the detected type and ask for confirmation before scanning** — never silently guess, and explicitly ask the user to split a scan when multiple type-signals are found in one path (monorepo) | Matches this plugin's established "don't guess" discipline (`/init existing`'s "not determined" rule, `/spec`'s Step 0 disambiguation prompt). A wrong silent classification would write real content into the wrong subfolder |
| Output shape | `.claude/docs/{backend,frontend,mobile}/` (only the subfolders actually scanned) + a cumulative `.claude/CLAUDE.md` index | Confirmed with the user — one merged `.claude/` tree per QA workspace, not one output tree per source repo |
| Repeat-run behavior | **Cumulative/additive** — each run only touches the subfolder(s) for the path(s) given this run; other subfolders and `CLAUDE.md`'s existing entries are left alone; `CLAUDE.md` gains a new entry, never loses one | User's explicit call — supports the realistic workflow of scanning backend today, frontend next week |
| Per-subfolder re-scan | If the **same** type's subfolder already has content (re-scanning the same repo, or scanning a second repo of the same type), ask overwrite / merge / cancel — scoped to that one subfolder only | Mirrors `/init existing`'s B1 existing-`.claude/`-check, narrowed to per-subfolder scope since this command can have 3 independent subfolders in flight |
| `autotest/` category | **Dropped** — `/scan-source` never scans the test-tooling repo itself | User's explicit correction mid-brainstorm; that job stays with `/init existing` |

## Scope

**In scope:**
- Accept 1+ local paths as positional arguments.
- Per path: run detection heuristics (see below), show the result, wait for
  user confirmation (or a corrected type, or a request to split a monorepo
  path into multiple scans).
- Per confirmed type, scan the path and write grounded docs to
  `.claude/docs/<type>/` (3 files per type — see Components).
- Merge-vs-overwrite-vs-cancel prompt when re-scanning into an
  already-populated subfolder.
- Update `.claude/CLAUDE.md` with a cumulative index entry per scan (source
  path, type, timestamp, one-paragraph summary) — never removing prior
  entries.
- Same grounding discipline as `/init existing`: every claim traces to real
  code found in the scanned path; "not determined" instead of guessing.

**Out of scope:**
- Cloning a remote repo — the user does this themselves.
- Scanning the autotest/test-tooling repo itself — stays `/init existing`'s job.
- Generating spec.md / feature files / any test-generation output directly —
  `/scan-source` produces reference material a human (or a future
  `FeatureGenerator`) reads, same boundary `/init existing` and `/spec`
  already draw for this plugin's Phase 1.
- MCP/remote-API-based scanning (e.g. GitHub API without a local clone) — not
  needed since cloning is the user's responsibility.

## Components

| File | Purpose |
|---|---|
| `commands/scan-source.md` | The entire feature — argument parsing, per-path detection + confirmation, per-type scan + doc-writing, cumulative `CLAUDE.md` index update. No companion script (same rationale as `/init` and `/spec`: requires reading and classifying arbitrary code). |

## Detection heuristics (per path, run before asking for confirmation)

Check for these signals, in this order, and report every signal actually
found (not just the first match — needed for the monorepo-ambiguity case):

| Type | Signals |
|---|---|
| **Mobile** | `android/` + `ios/` directories at the path's root; `pubspec.yaml` (Flutter); `app.json` containing an `"expo"` key; a `package.json` dependency on `react-native`; any `*.xcodeproj`/`*.xcworkspace`; `AndroidManifest.xml`; `Info.plist` |
| **Frontend** | A `package.json` dependency on `react`, `vue`, `svelte`, `@angular/core`, `next`, or `nuxt`; an `index.html` at or near the root alongside a bundler config (`vite.config.*`, `webpack.config.*`); a `src/components/` or `src/pages/` directory |
| **Backend** | A `package.json` dependency on `express`, `fastify`, `@nestjs/core`, or `koa`; OR non-JS manifests: `requirements.txt`/`pyproject.toml` containing `flask`/`django`/`fastapi`; `go.mod`; `pom.xml`/`build.gradle` containing a Spring Boot dependency (and no `android { ... }` block, which would indicate Android instead); a `Gemfile` containing `rails`; a `controllers/`, `routes/`, or `migrations/` directory; a `Dockerfile` exposing a server port |

## Data flow

```
/scan-source <path1> [path2] ...
  For each path, in order given:
    1. Run the detection heuristics table above against the path. Collect
       every signal found (not just the first match).
    2. Show the result:
         "Path: <path>
          Detected: <type> (based on: <specific signals found>)
          Correct? (y / n — choose a different type)"
       If signals for MORE THAN ONE type were found (monorepo case), show all
       detected types and ask the user whether to scan this path as one type
       now (which?) or split it into separate scans by giving narrower
       sub-paths.
       If NO signal matched any type, ask the user directly what type this
       is (backend / frontend / mobile) — never guess.
       Wait for the reply before proceeding.
    3. Check .claude/docs/<confirmed-type>/ for existing content.
         Empty/missing → proceed to scan.
         Has content → ask: overwrite this subfolder / merge (fill in only
         missing files) / skip this path. Wait for the reply.
    4. Scan the path (Read/Grep/Glob — same tools/discipline as
       /init existing's B2): read package.json/equivalent manifest, key
       source directories, and 2-3 representative files, to ground every
       claim in real code found. Never guess; write "not determined" for
       anything not evidenced.
    5. Write the 3 files for the confirmed type (see per-type content below)
       to .claude/docs/<type>/, honoring the overwrite/merge/skip choice
       from step 3.
    6. Update .claude/CLAUDE.md: append (or update, if this exact source
       path was scanned before) one entry — source path, type, timestamp,
       and a 1-2 line summary of what was found. Never remove other
       entries.
  After all given paths are processed: report every subfolder written
  (or skipped) with a 1-2 line summary each, mirroring /init existing's B5
  report style.
```

## Per-type file content

**`backend/`:**
- `architecture.md` — layers present (controller/service/repository/etc.,
  only ones that actually exist), key libraries/frameworks, database
  technology if evidenced.
- `api-contracts.md` — real endpoints found in route/controller code: method,
  path, request/response shape. "not determined" for anything not found.
- `business-logic.md` — domain rules/validations found in real code (e.g. a
  validation constant, a business rule check) — grounded, never invented.

**`frontend/`:**
- `architecture.md` — component layers, state-management library, routing
  library, key build tooling.
- `components.md` — key components found, with their real `data-testid`/
  selector attributes as they appear in the code.
- `routes.md` — real page routes/URL patterns and the navigation flow
  between them, as evidenced by the routing config/code.

**`mobile/`:**
- `architecture.md` — screen layer, navigation library, state-management
  approach.
- `screens.md` — real screens found, with their accessibility-id/testID
  attributes as they appear in the code.
- `navigation.md` — the navigation graph/flow between screens, as evidenced
  by the routing/navigation code.

Every file follows the same grounding rule as `/init existing`: claims trace
to real code; write the literal string "not determined" for anything not
evidenced, never invent.

## `.claude/CLAUDE.md` cumulative index format

```markdown
# Scanned Sources

## <type> — <source path>
**Last scanned:** <ISO timestamp>
<1-2 line summary of what was found>
See: .claude/docs/<type>/

## <type> — <another source path>
...
```

New scans append a new `##` entry (or update the matching entry in place if
the exact same source path is re-scanned); existing entries for other source
paths are never removed.

## Error / edge handling

| Situation | Behavior |
|---|---|
| No path arguments given | Usage error: "/scan-source needs at least one path", stop |
| A given path doesn't exist / isn't readable | Report it, skip that path, continue with the rest |
| A path matches signals for more than one type (monorepo) | Show all matched types, ask the user to pick one type for this path or split into narrower sub-paths — never guess |
| A path matches no type signal at all | Ask the user directly what type it is — never guess |
| User declines the detected type (`n`) | Ask which type it actually is, then proceed with that instead |
| Re-scan of an already-populated subfolder, user picks "skip" | Leave that subfolder untouched, note "skipped" in the final report, continue with other paths |
| Nothing determinable for a given file's content (e.g. no API routes found in a backend repo) | Write "not determined" in that file's relevant section — never invent an example |

## Follow-ups (not this spec)

- Feeding `/scan-source`'s output automatically into `/spec` as a Step-0-style
  source (today it's just reference material a human or a future
  `FeatureGenerator` reads) — not requested, would need its own design.
- MCP/remote scanning without a local clone — not requested; the user
  explicitly owns cloning.

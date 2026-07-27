# Design: `/do-cucumber-task` grounds locators against the real saved source

## Context

`/scan-source` (mobile-depth round, `docs/superpowers/plans/2026-07-24-scan-source-mobile-depth.md`)
already: supports no-arg rescan, records `MOBILE_PLATFORM` (Android/iOS/both),
generates `locators.md` (Appium locators, Compose Testing, iOS accessibility
identifiers) and `directory-tree.md`, and persists the scanned path per type
in `.claude/CLAUDE.md`'s `# Scanned Sources` section as
`## <type> — <path>` entries.

What's still missing: when `/do-cucumber-task` needs a locator value for a
specific scenario, its "Resolve the grounding/selector source" step
(`commands/do-cucumber-task.md`) only offers two choices for `mobile`
(scanned `.claude/docs/mobile/screens.md` summary, or a live Appium
connection) and two for `frontend` (scanned `.claude/docs/frontend/
components.md`, or a live URL). Neither reads the real source file directly
from the path `/scan-source` already saved — the scanned summary can be
stale, and live connection requires a running app/device that may not be
available while writing tests ahead of a build.

This round ("Part 2") closes that gap: `/do-cucumber-task` reads the real,
current source file at the saved path when possible, before falling back to
the existing scanned/live choice.

**Scope:** `mobile` and `frontend`. `backend` is unchanged (it already
grounds directly against `specs/*/spec.md` / `.claude/docs/backend/`, no
selector step exists for it).

## Architecture

Two files change:

1. **`commands/scan-source.md`** (prerequisite, small addition) — each
   entry written to `.claude/docs/mobile/screens.md` and
   `.claude/docs/frontend/components.md` gains a `**File:**` line recording
   the real file path (relative to the scanned `<path>`) it was grounded
   from. This is the only way `/do-cucumber-task` can later jump straight to
   the right file. This is scoped as its own small task in the Part 2
   implementation plan — it does not modify Task 6 of the
   `scan-source-mobile-depth` plan, which is unchanged and still pending on
   its own.

2. **`commands/do-cucumber-task.md`** — the "Resolve the grounding/selector
   source" section's `mobile` and `frontend` branches gain a new first
   choice: read the real source file at the saved path. The existing
   scanned/live choice becomes the fallback, unchanged in its own behavior.

## Data flow

For `mobile` and `frontend` (replaces today's immediate scanned/live ask):

```
1. Read .claude/CLAUDE.md, find "## mobile — <SAVED_PATH>" (or
   "## frontend — <SAVED_PATH>") for the current PLATFORM.
2. SAVED_PATH missing, or not present/readable on disk (ls/test -d/-r
   fails, e.g. deleted, moved to another machine, permission denied)
     → unchanged legacy behavior: ask scanned/live (mobile) or
       scanned/live+URL (frontend), exactly as today.
3. SAVED_PATH present and readable:
   a. Look for a MODULE-matching entry in screens.md/components.md with a
      recorded **File:** path.
      → Found, and the file still exists at SAVED_PATH/<File> → open it,
        extract current selector values directly from the real file. Set
        SELECTOR_SOURCE=source.
      → Found, but the file no longer exists at that path (renamed/moved/
        deleted since the last scan) → treat as not-found, go to 3b.
      → No screens.md/components.md at all for this platform → skip
        straight to 3b (nothing to match against).
   b. No matching entry (new screen/component never scanned) → fall back
      to a find/grep search under SAVED_PATH using a name derived from
      MODULE (case-insensitive substring match on file/type name).
      → Exactly one match → open and use it. Set SELECTOR_SOURCE=source.
      → Zero or 2+ matches → print whatever candidates were found (if
        any), then ask the user to either paste the real file path
        directly, or reply `skip` to fall back to the legacy scanned/live
        ask.
```

No new question is asked when step 3 resolves unambiguously (3a hit, or 3b
exactly-one-match) — the whole point is removing an unnecessary prompt when
the ground truth is available and cheap to read. The user is only asked
when the saved path is gone, or when the fallback search is ambiguous.

`SELECTOR_SOURCE` gains a fourth value, `source` (alongside the existing
`scanned`/`live`/`none`), and the final Report states which one was used
per module — so a QA reading the output can judge confidence (source > 
scanned > live > none, in terms of freshness/trust, independent of token
cost).

## Error handling / edge cases

- Recorded **File:** path stale (file moved/renamed/deleted) → falls back
  to 3b's find/grep search, not a hard error.
- Real file opened but no selector-like attribute found in it (code
  refactored, testTag removed) → record "not determined" for that element,
  same no-guessing rule already in place elsewhere in this command.
- SAVED_PATH unreadable due to permissions → treated identically to
  "path missing" (step 2), falls back to the legacy ask.
- `screens.md`/`components.md` deleted manually while `CLAUDE.md`'s path
  entry still exists → treated as "no matching entry", goes to 3b.
- `backend` — entirely unchanged, no selector step exists for it.

## Testing approach

No automated test framework for this command (prose/markdown Claude Code
plugin command, consistent with how Tasks 4/5 of the mobile-depth round
were verified). Verification means:

- `grep` checks confirming the markdown edits landed at the right
  locations in both files (matching the pattern used in Tasks 1-5).
- Scratch-directory smoke tests with real files, run under `zsh -c '...'`
  (not the default shell) given this environment's zsh-specific glob
  behavior found and fixed in Task 4:
  - A fake SAVED_PATH with one real source file containing a real
    testTag/accessibility-id/data-testid → confirm the value is read
    directly from that file, matching the value literally.
  - A screens.md/components.md entry whose **File:** points to a path that
    no longer exists → confirm the find/grep fallback (3b) triggers
    instead of erroring.
  - A MODULE with zero fallback matches → confirm the user is asked to
    supply a path or reply `skip`, and that `skip` reproduces today's
    scanned/live ask unchanged.
  - SAVED_PATH itself missing entirely → confirm the legacy scanned/live
    ask fires exactly as it does today (regression check — this path must
    not change behavior).

## Out of scope

- `backend` platform (already grounds directly against specs/docs, no
  selector step).
- Any change to the live Appium/Playwright connection flows themselves —
  they remain exactly as they are today, just demoted to fallback.
- Task 6 of `scan-source-mobile-depth` (cumulative index `Platform:` line,
  Report wording) — unrelated, still pending on its own, not touched here.

---
name: refactor-code
description: Scan the current project (or a scoped path/glob) for refactor issues, list them numbered 1–N, then wait for the user to select which ones to fix.
argument-hint: "[path-or-glob]"
---

EXECUTE IMMEDIATELY.

Run an interactive refactor session on the current project.

`$ARGUMENTS` is an optional path or glob that scopes the review (e.g.
`src/pages/`, `src/step-definitions/**/*.ts`). If omitted, scan from the
project root.

---

## Phase 1 — Scan

Read the target files and collect every refactor-worthy problem. Skip
`node_modules/`, `dist/`, `.next/`, `build/`, and `coverage/`.

File types to scan: `*.ts`, `*.js`, `*.tsx`, `*.jsx`, `*.feature`.

For each problem found, record:

- **ID** — sequential integer starting at 1
- **Severity** — `HIGH` or `MEDIUM`
- **Category** — one of: `anti-pattern`, `hardcode`, `architecture`,
  `duplication`, `naming`
- **Location** — `path/to/file.ts:LINE`
- **Problem** — one sentence, specific (not generic advice)
- **Fix** — the concrete change to make (not a suggestion — show the
  exact replacement)

Look for, but do not limit to:

| Category | Examples |
|---|---|
| `anti-pattern` | `waitForTimeout`, `page.pause()`, `eval()`, unchecked `any` casts in critical paths |
| `hardcode` | Literal email addresses, passwords, URLs, environment-specific strings in feature files or step definitions |
| `architecture` | Module-level mutable variables shared across scenarios, missing `await` on async calls, direct DOM manipulation instead of page-object methods |
| `duplication` | Near-identical step definition blocks that can be extracted to a shared helper |
| `naming` | Misleading identifiers, Hungarian notation, single-letter variables outside loops |

---

## Phase 2 — Display Issues

Print every issue found using this exact format, then stop:

```
[1] HIGH | anti-pattern | src/pages/Login.ts:23
    waitForTimeout(3000) used — blocks the runner and hides real timing.
    → Replace with: await expect(page.locator('[data-testid="submit"]')).toBeVisible()

[2] HIGH | hardcode | src/features/Login.feature:15
    Email "autotest-user@yopmail.com" hardcoded in feature file.
    → Move to a test-data config file or environment variable; reference via a placeholder.

[3] MEDIUM | architecture | src/step-definitions/login.steps.ts:8
    loginPage declared at module level — shared state causes race conditions between scenarios.
    → Declare inside the step function: const loginPage = new LoginPage(page);
```

After the last issue, print exactly:

```
── N issue(s) found ──
Reply with:
  • A number or range  (e.g. "1", "3,5", "1-4")
  • "all" to fix everything
  • "skip" to exit without changes
```

Then **stop and wait for the user's reply**. Do not apply any fix yet.

---

## Phase 3 — Fix Selected Issues

Parse the user's reply:

| Reply | Action |
|---|---|
| `"all"` | Fix every issue in ID order |
| `"1-4"` | Fix issues 1, 2, 3, 4 |
| `"1,3,5"` | Fix issues 1, 3, and 5 |
| A single number | Fix that one issue |
| `"skip"` or empty | Exit — report nothing was changed |

For each selected issue, in ID order:

1. Re-read the affected file to confirm the code still matches what was scanned.
2. **Matches** — apply the fix. Report: `✓ [N] Fixed: path/to/file.ts:LINE`
3. **Does not match** — do not guess. Report: `✗ [N] Skipped: file changed since scan — left untouched.`
4. **Fix touches more than 3 files** — before applying, warn:
   `"Fix [N] touches X files — proceed? (y/n)"` and wait for the reply.
   If the user replies `n`, skip and report it as skipped.

After all selected fixes are attempted, print a summary:

```
── Refactor Summary ────────────────────────────────
✓ Fixed:   [1] src/pages/Login.ts:23
✓ Fixed:   [3] src/step-definitions/login.steps.ts:8
✗ Skipped: [2] file changed since scan
────────────────────────────────────────────────────
No commits or pushes made. Review changes before committing.
```

---

## Rules

- Fix only the issues listed. Do not clean up surrounding code opportunistically.
- Never rename a public API or exported identifier without explicitly noting
  which callers are affected and what they must update.
- Never commit or push. Leave version control to the user.
- If a fix cannot be applied cleanly, leave the file untouched and report it.

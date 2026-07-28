---
name: add-mcp
description: Add an MCP server to the current project's .mcp.json from a curated catalog of verified packages (playwright, github, appium, azure-devops, jira, cucumberstudio). Never invents package names — only the catalog below. Writes to the project, not the plugin, so filled-in credentials survive every future plugin update.
argument-hint: "[playwright|github|appium|azure-devops|jira|cucumberstudio]"
---

EXECUTE IMMEDIATELY.

The catalog (package names, args, env placeholders) and all file-writing
logic live in `scripts/add-mcp.sh` — this command only drives the
conversation around it. Never reimplement its logic inline; always call the
script. Valid keys: `playwright github appium azure-devops jira cucumberstudio`.

The script writes to `.mcp.json` in the current working directory (the
user's own project root) — never into this plugin's own files. This is
deliberate: `.mcp.json` is outside anything a plugin update/reinstall
touches, so a real credential the user fills in survives every future
version bump. Run this command from the project root, not from inside the
plugin's own repo.

## 1. Resolve which entry

- If `$ARGUMENTS` matches a valid key exactly, use it directly.
- If no argument (or it doesn't match), list the 6 keys and ask the user to
  pick one. Do not guess — wait for their answer.

## 2. Collect entry-specific input

- `azure-devops`: ask for the Azure DevOps org name — it becomes `--org
  <org-name>` below.
- All other entries: no extra input needed. **Never ask the user to paste a
  real token/secret into chat** — the script always writes placeholder
  values for those.

## 3. Dry run

Run from the project (this resolves the script's own absolute path via
`${CLAUDE_PLUGIN_ROOT}`, so it works no matter what directory the user is
in — never call it as a bare relative `scripts/add-mcp.sh`, that only
works by accident if the cwd happens to be the plugin's own directory):
```bash
bash "${CLAUDE_PLUGIN_ROOT}/scripts/add-mcp.sh" <key> [--org <org-name>]
```

- If it exits non-zero because the entry already exists, it prints the
  existing config — show that to the user and ask: overwrite (re-run step 3
  with `--force` added) or skip (stop, no files touched)?
- If it exits non-zero for any other reason (bad key, missing org), show the
  error and stop.

## 4. Confirm

Show the script's preview output to the user and ask for explicit
confirmation before writing. If declined, stop — no files touched.

## 5. Apply

On confirmation, run:
```bash
bash "${CLAUDE_PLUGIN_ROOT}/scripts/add-mcp.sh" <key> [--org <org-name>] --apply [--force]
```
(include `--force` only if this is an intentional overwrite, per step 3).
Report its output to the user as-is (it already includes the
placeholder/git-exclude/reload reminders).

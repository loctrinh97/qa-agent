---
name: add-mcp
description: Add an MCP server to this plugin's mcpServers config from a curated catalog of verified packages (playwright, github, appium, azure-devops, jira, cucumberstudio). Never invents package names — only the catalog below.
argument-hint: "[playwright|github|appium|azure-devops|jira|cucumberstudio]"
---

EXECUTE IMMEDIATELY.

The catalog (package names, args, env placeholders) and all file-writing
logic live in `scripts/add-mcp.sh` — this command only drives the
conversation around it. Never reimplement its logic inline; always call the
script. Valid keys: `playwright github appium azure-devops jira cucumberstudio`.

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

Run (from the plugin root):
```bash
bash scripts/add-mcp.sh <key> [--org <org-name>]
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
bash scripts/add-mcp.sh <key> [--org <org-name>] --apply [--force]
```
(include `--force` only if this is an intentional overwrite, per step 3).
Report its output to the user as-is (it already includes the
placeholder/git/reload reminders).

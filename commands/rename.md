---
name: rename
description: Rename this plugin's id (the "name" field in plugin.json) across every file that must stay in sync — plugin.json, marketplace.json's plugin entry, and the install line in README.md. Does not touch the marketplace's own name.
argument-hint: "<new-name>"
---

EXECUTE IMMEDIATELY.

All validation and file-writing logic lives in `scripts/rename.sh` — this
command only drives the conversation around it. Never reimplement its logic
inline; always call the script.

## 1. Dry run

Run (from the plugin root):
```bash
bash scripts/rename.sh "$ARGUMENTS"
```

If it exits non-zero, show the error message to the user verbatim and stop
(bad/missing argument, or nothing to rename).

## 2. Confirm

Show the script's preview output to the user and ask for explicit
confirmation before proceeding. If declined, stop — no files touched.

## 3. Apply

On confirmation, run:
```bash
bash scripts/rename.sh "$ARGUMENTS" --apply
```
Report its output to the user as-is (it already includes the git/reload
reminders).

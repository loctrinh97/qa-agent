#!/usr/bin/env bash
# Rename this plugin's id across plugin.json, marketplace.json, and README.md.
#
# Usage:
#   rename.sh <new-name>           dry run — validates and prints a preview, writes nothing
#   rename.sh <new-name> --apply   performs the rename
set -euo pipefail

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PLUGIN_JSON="$DIR/.claude-plugin/plugin.json"
MARKETPLACE_JSON="$DIR/.claude-plugin/marketplace.json"
README="$DIR/README.md"

NEW_NAME="${1:-}"
APPLY=false
[[ "${2:-}" == "--apply" ]] && APPLY=true

if [[ -z "$NEW_NAME" ]]; then
  echo "Usage: rename.sh <new-name> [--apply]" >&2
  exit 1
fi

if ! [[ "$NEW_NAME" =~ ^[a-z][a-z0-9]*(-[a-z0-9]+)*$ ]]; then
  echo "Invalid name \"$NEW_NAME\": must be lowercase letters/digits, hyphen-separated segments, no leading/trailing/double hyphens, no ':' or '_'." >&2
  exit 1
fi

if [[ ! -f "$PLUGIN_JSON" ]]; then
  echo "plugin.json not found at $PLUGIN_JSON" >&2
  exit 1
fi

OLD_NAME="$(grep -m1 '"name"' "$PLUGIN_JSON" | sed -E 's/.*"name": *"([^"]+)".*/\1/')"

if [[ "$OLD_NAME" == "$NEW_NAME" ]]; then
  echo "Already named \"$NEW_NAME\" — nothing to rename."
  exit 1
fi

echo "Rename plugin: $OLD_NAME -> $NEW_NAME"
echo
echo "Files to update:"
[[ -f "$PLUGIN_JSON" ]] && echo "  .claude-plugin/plugin.json        \"name\": \"$OLD_NAME\" -> \"$NEW_NAME\""
[[ -f "$MARKETPLACE_JSON" ]] && echo "  .claude-plugin/marketplace.json   plugins[].name: \"$OLD_NAME\" -> \"$NEW_NAME\" (top-level marketplace name untouched)"
[[ -f "$README" ]] && echo "  README.md                         ${OLD_NAME}@... -> ${NEW_NAME}@..."

if ! $APPLY; then
  echo
  echo "(dry run — re-run with --apply to write these changes)"
  exit 0
fi

if [[ -f "$PLUGIN_JSON" ]]; then
  sed -i.bak "s/\"name\": \"$OLD_NAME\"/\"name\": \"$NEW_NAME\"/" "$PLUGIN_JSON"
  rm -f "$PLUGIN_JSON.bak"
fi
if [[ -f "$MARKETPLACE_JSON" ]]; then
  sed -i.bak "s/\"name\": \"$OLD_NAME\"/\"name\": \"$NEW_NAME\"/" "$MARKETPLACE_JSON"
  rm -f "$MARKETPLACE_JSON.bak"
fi
if [[ -f "$README" ]]; then
  sed -i.bak "s/${OLD_NAME}@/${NEW_NAME}@/g" "$README"
  rm -f "$README.bak"
fi

echo
echo "Done. No git command was run — review with git status/git diff and commit yourself."

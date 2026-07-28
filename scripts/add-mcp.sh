#!/usr/bin/env bash
# Add an MCP server entry to the CURRENT PROJECT's .mcp.json (project root),
# from a fixed catalog of verified packages. Never invents package names.
#
# .mcp.json lives in the user's own project, not inside this plugin's
# installed files — so it survives every future plugin version bump/update.
# Filled-in real secrets never need to be re-entered after an upgrade.
#
# Usage:
#   add-mcp.sh <key> [--org <org-name>]              dry run — prints what would be added
#   add-mcp.sh <key> [--org <org-name>] --apply       writes the change
#   add-mcp.sh <key> [--org <org-name>] --apply --force   overwrite an existing entry
#
# Valid keys: playwright github appium azure-devops jira cucumberstudio
set -euo pipefail

MCP_JSON="$PWD/.mcp.json"

KEY="${1:-}"
shift || true

ORG=""
APPLY=false
FORCE=false
while [[ $# -gt 0 ]]; do
  case "$1" in
    --org) ORG="${2:-}"; shift 2 ;;
    --apply) APPLY=true; shift ;;
    --force) FORCE=true; shift ;;
    *) echo "Unknown option: $1" >&2; exit 1 ;;
  esac
done

VALID_KEYS="playwright github appium azure-devops jira cucumberstudio"

case "$KEY" in
  playwright)
    ENTRY='{"command":"npx","args":["@playwright/mcp@latest"]}'
    ;;
  github)
    ENTRY='{"command":"npx","args":["-y","@modelcontextprotocol/server-github"],"env":{"GITHUB_PERSONAL_ACCESS_TOKEN":"<YOUR_GITHUB_TOKEN>"}}'
    ;;
  appium)
    ENTRY='{"command":"npx","args":["appium-mcp@latest"],"env":{"NO_UI":"true"}}'
    ;;
  azure-devops)
    if [[ -z "$ORG" ]]; then
      echo "azure-devops requires --org <org-name>" >&2
      exit 1
    fi
    ENTRY=$(python3 -c "import json,sys; print(json.dumps({'command':'npx','args':['-y','@azure-devops/mcp', sys.argv[1]]}))" "$ORG")
    ;;
  jira)
    ENTRY='{"command":"npx","args":["-y","mcp-atlassian"],"env":{"ATLASSIAN_BASE_URL":"<YOUR_ATLASSIAN_BASE_URL>","ATLASSIAN_EMAIL":"<YOUR_ATLASSIAN_EMAIL>","ATLASSIAN_API_TOKEN":"<YOUR_ATLASSIAN_API_TOKEN>"}}'
    ;;
  cucumberstudio)
    ENTRY='{"command":"npx","args":["cucumberstudio-mcp"],"env":{"CUCUMBERSTUDIO_ACCESS_TOKEN":"<YOUR_CUCUMBERSTUDIO_ACCESS_TOKEN>","CUCUMBERSTUDIO_CLIENT_ID":"<YOUR_CUCUMBERSTUDIO_CLIENT_ID>","CUCUMBERSTUDIO_UID":"<YOUR_CUCUMBERSTUDIO_EMAIL>"}}'
    ;;
  *)
    echo "Usage: add-mcp.sh <key> [--org <org-name>] [--apply] [--force]" >&2
    echo "Valid keys: $VALID_KEYS" >&2
    exit 1
    ;;
esac

EXISTS="$(python3 -c "
import json, os
path = '$MCP_JSON'
if not os.path.exists(path):
    print('no')
else:
    with open(path) as f:
        d = json.load(f)
    print('yes' if '$KEY' in d.get('mcpServers', {}) else 'no')
")"

if [[ "$EXISTS" == "yes" && "$FORCE" != "true" ]]; then
  echo "mcpServers.\"$KEY\" already exists in .mcp.json:"
  python3 -c "
import json
with open('$MCP_JSON') as f:
    d = json.load(f)
print(json.dumps(d['mcpServers']['$KEY'], indent=2))
"
  echo
  echo "Re-run with --force to overwrite, or choose skip."
  exit 1
fi

echo "Add MCP server \"$KEY\" to .mcp.json (project root: $PWD):"
python3 -c "
import json
print(json.dumps({'$KEY': json.loads('''$ENTRY''')}, indent=2, ensure_ascii=False))
"
echo
echo "Placeholders like <YOUR_...> are NOT real credentials — fill them in by hand afterward, and never commit real tokens."
echo "This file lives in your project, not inside the plugin, so it survives every future plugin version bump/update — you will not need to re-add this MCP server or re-enter its credentials again."

if [[ "$KEY" == "github" ]]; then
  echo
  echo "Note: @modelcontextprotocol/server-github carries an upstream deprecation notice (moved to github/github-mcp-server) but still installs and runs fine via npx."
fi

if ! $APPLY; then
  echo
  echo "(dry run — re-run with --apply to write this change)"
  exit 0
fi

python3 -c "
import json, os
path = '$MCP_JSON'
if os.path.exists(path):
    with open(path) as f:
        d = json.load(f)
else:
    d = {}
d.setdefault('mcpServers', {})['$KEY'] = json.loads('''$ENTRY''')
with open(path, 'w') as f:
    json.dump(d, f, indent=2, ensure_ascii=False)
    f.write('\n')
"

GIT_DIR="$(git rev-parse --git-dir 2>/dev/null || true)"
if [[ -n "$GIT_DIR" ]]; then
  EXCLUDE_FILE="$GIT_DIR/info/exclude"
  mkdir -p "$(dirname "$EXCLUDE_FILE")"
  touch "$EXCLUDE_FILE"
  if ! grep -qxF ".mcp.json" "$EXCLUDE_FILE" 2>/dev/null; then
    echo ".mcp.json" >> "$EXCLUDE_FILE"
    echo
    echo "Added .mcp.json to .git/info/exclude (local-only — never touches your tracked .gitignore). It won't show up in git status and can't be committed by accident."
  fi
fi

echo
echo "Done. No git command was run — review with git status/git diff yourself if you want to confirm."
echo "Restart Claude Code (or start a new session) in this project for the new MCP server to connect — .mcp.json changes aren't picked up by a running session."

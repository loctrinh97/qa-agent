# lian-qa-plugin

Personal Claude Code plugin. Commands are added incrementally — none yet.

## Install (local marketplace)

```bash
/plugin marketplace add /Users/lian.trinh/SourceCode/setup-qa-plugin/lian-qa-plugin
/plugin install lian-qa-plugin@lian-plugins
```

## Structure

- `.claude-plugin/plugin.json` — plugin manifest
- `.claude-plugin/marketplace.json` — single-plugin marketplace listing (enables local install above)
- `commands/` — slash commands (empty for now)

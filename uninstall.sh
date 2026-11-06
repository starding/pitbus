#!/bin/zsh
# Remove pit's LaunchAgents, app, command and skill. Keeps the data in ~/Library/Application Support/pit.
UIDN=$(id -u)
for label in dev.pit.daemon dev.pit.menubar; do
  launchctl bootout "gui/$UIDN/$label" 2>/dev/null
  rm -f "$HOME/Library/LaunchAgents/$label.plist"
done
rm -rf "$HOME/Applications/PitBus.app" "$HOME/Applications/PitBar.app" "$HOME/.claude/skills/pit-watch"
rm -f "$HOME/.local/bin/pit"
command -v claude >/dev/null && claude mcp remove --scope user pit >/dev/null 2>&1
python3 - "$HOME/.claude/settings.json" <<'PYEOF'
import json, os, sys
path = sys.argv[1]
if os.path.exists(path):
    cfg = json.load(open(path))
    post = cfg.get("hooks", {}).get("PostToolUse", [])
    keep = [e for e in post if not any("pit hook-sent" in h.get("command", "") for h in e.get("hooks", []))]
    if keep != post:
        cfg["hooks"]["PostToolUse"] = keep
        json.dump(cfg, open(path, "w"), ensure_ascii=False, indent=2)
PYEOF
echo "pit removed (data kept in ~/Library/Application Support/pit)"

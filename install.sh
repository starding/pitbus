#!/bin/zsh
# Install pit: the `pit` command, the daemon and the menu bar app as LaunchAgents, and the Claude Code skill.
# Re-run to update. Undo with ./uninstall.sh.
#
#   ./install.sh             every source on; builds the menu bar app unless a prebuilt PitBus.app is in the package
#   ./install.sh --minimal   Slack only: the other sources and the local model start off, and their tools are not needed
#
# What only the person can do (sign in, install Python) is never done here: it is listed at the end.
set -euo pipefail

ROOT=${0:A:h}
DATA="$HOME/Library/Application Support/pit"
AGENTS="$HOME/Library/LaunchAgents"
APP="$HOME/Applications/PitBus.app"
UIDN=$(id -u)
MINIMAL=0
for a in "$@"; do [[ $a == --minimal ]] && MINIMAL=1; done
TODO=()
SLACKCTL_VERSION=0.2.4

# 0. Python: without Xcode's command line tools, /usr/bin/python3 is only a stub that asks to install them
if ! PY=$(command -v python3) || { [[ $PY == /usr/bin/python3 ]] && ! xcode-select -p >/dev/null 2>&1; }; then
  echo "需要你本人先装 Python 3：从 https://www.python.org/downloads/macos/ 下载安装包装上，再重新运行 ./install.sh"
  exit 1
fi

mkdir -p "$DATA/dossiers" "$DATA/sources" "$HOME/.local/bin" "$AGENTS" "$HOME/Applications" "$HOME/.claude/skills/pit-watch"

# 1. slackctl, the one tool every install needs: the public release, checked against its published checksums
if ! command -v slackctl >/dev/null && [[ ! -x $HOME/.local/bin/slackctl ]]; then
  arch=$([[ $(uname -m) == arm64 ]] && echo arm64 || echo amd64)
  tgz="slackctl_darwin_${arch}.tar.gz"
  base="https://github.com/Cluas/slackctl/releases/download/v$SLACKCTL_VERSION"
  tmp=$(mktemp -d)
  echo "安装 slackctl $SLACKCTL_VERSION …"
  curl -fsSL -o "$tmp/$tgz" "$base/$tgz"
  curl -fsSL -o "$tmp/checksums.txt" "$base/checksums.txt"
  want=$(awk -v f="$tgz" '$2 == f {print $1}' "$tmp/checksums.txt")
  got=$(shasum -a 256 "$tmp/$tgz" | awk '{print $1}')
  [[ -n $want && $want == $got ]] || { echo "slackctl 下载校验失败，已停止"; exit 1; }
  tar -xzf "$tmp/$tgz" -C "$tmp" slackctl
  install -m 755 "$tmp/slackctl" "$HOME/.local/bin/slackctl"
  rm -rf "$tmp"
fi
SLACKCTL=$(command -v slackctl || echo "$HOME/.local/bin/slackctl")
if ! "$SLACKCTL" auth test >/dev/null 2>&1; then
  TODO+=("登录 Slack：先打开并登录 Slack 桌面版，然后在终端运行 $SLACKCTL auth import-desktop，再运行 $HOME/.local/bin/pit config")
fi

# 2. command line
cat > "$HOME/.local/bin/pit" <<EOF
#!/bin/sh
exec "$PY" "$ROOT/pit/pit.py" "\$@"
EOF
chmod +x "$HOME/.local/bin/pit"
PIT="$HOME/.local/bin/pit"
# who the person is comes from the signed-in slackctl and lark-cli; PIT_* override it
PATH="$HOME/.local/bin:$PATH" "$PIT" config ${PIT_SLACK_USER:+--slack-user "$PIT_SLACK_USER"} \
  ${PIT_LARK_OPEN_ID:+--lark-open-id "$PIT_LARK_OPEN_ID"} ${PIT_NAME:+--name "$PIT_NAME"} \
  ${PIT_STYLE_SKILL:+--style-skill "$PIT_STYLE_SKILL"} >/dev/null
if (( MINIMAL )); then
  for s in lark_doc gcal github system; do "$PIT" set "source.$s" off >/dev/null; done
  "$PIT" set classifier.backend off >/dev/null
fi

# 3. menu bar app: the package's prebuilt one when there is one, else built here (needs Xcode's command line tools)
rm -rf "$HOME/Applications/PitBar.app"  # the earlier name
rm -rf "$APP"
if [[ -d $ROOT/PitBus.app ]]; then
  cp -R "$ROOT/PitBus.app" "$APP"
  # a download carries a quarantine mark that would stop launchd from starting an unsigned app
  xattr -dr com.apple.quarantine "$APP" 2>/dev/null || true
else
  mkdir -p "$ROOT/menubar/build" "$APP/Contents/MacOS"
  swiftc -O "$ROOT"/menubar/*.swift -o "$ROOT/menubar/build/PitBus"
  cp "$ROOT/menubar/build/PitBus" "$APP/Contents/MacOS/PitBus"
  sh "$ROOT/menubar/info-plist.sh" > "$APP/Contents/Info.plist"
fi

# 4. LaunchAgents: the daemon stays alive; the menu bar app starts at login
agent() {  # label, keepalive, program args...
  local label=$1 keep=$2; shift 2
  local args=""
  for a in "$@"; do args+="<string>$a</string>"; done
  cat > "$AGENTS/$label.plist" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>Label</key><string>$label</string>
  <key>ProgramArguments</key><array>$args</array>
  <key>RunAtLoad</key><true/>
  <key>KeepAlive</key><$keep/>
  <key>StandardOutPath</key><string>$DATA/$label.log</string>
  <key>StandardErrorPath</key><string>$DATA/$label.log</string>
</dict></plist>
EOF
  [[ -n ${PIT_NO_LAUNCHD:-} ]] && return  # a test install in a throwaway home starts nothing
  launchctl bootout "gui/$UIDN/$label" 2>/dev/null || true
  # bootout returns before the job is gone; bootstrapping too early fails with an I/O error
  for _ in {1..50}; do launchctl print "gui/$UIDN/$label" >/dev/null 2>&1 || break; sleep 0.2; done
  launchctl bootstrap "gui/$UIDN" "$AGENTS/$label.plist"
}
agent dev.pit.daemon true "$PY" "$ROOT/pit/pit.py" daemon
agent dev.pit.menubar false "$APP/Contents/MacOS/PitBus"

# 5. Claude Code skill, and the MCP server Claude uses to read and add to pit (user scope: every project)
cp "$ROOT/skill/SKILL.md" "$HOME/.claude/skills/pit-watch/SKILL.md"
if command -v claude >/dev/null; then
  claude mcp remove --scope user pit >/dev/null 2>&1 || true
  claude mcp add --scope user pit -- "$PY" "$ROOT/pit/pit.py" mcp >/dev/null
else
  TODO+=("装上 Claude Code 命令行后重新运行 ./install.sh $*，Claude 才能通过 MCP 用上 PitBus")
fi

# 6. Claude Code hook: a Slack message a session sends with slackctl is recorded, and the conversation
#    is bound to that session, so the menu bar opens it instead of offering a new one
"$PY" - "$HOME/.claude/settings.json" "$PIT hook-sent" <<'PYEOF'
import json, os, sys
path, cmd = sys.argv[1], sys.argv[2]
cfg = json.load(open(path)) if os.path.exists(path) else {}
post = cfg.setdefault("hooks", {}).setdefault("PostToolUse", [])
if not any(h.get("command") == cmd for e in post for h in e.get("hooks", [])):
    post.append({"matcher": "Bash", "hooks": [{"type": "command", "command": cmd}]})
    json.dump(cfg, open(path, "w"), ensure_ascii=False, indent=2)
PYEOF

[[ ":$PATH:" == *":$HOME/.local/bin:"* ]] || \
  TODO+=("让终端找得到 pit 和 slackctl：在 ~/.zshrc 末尾加一行 export PATH=\"\$HOME/.local/bin:\$PATH\"，然后重开终端")
TODO+=("不要移动或删除这个文件夹（$ROOT）：PitBus 从这里运行")

echo "PitBus 已安装：菜单栏应用和后台服务已启动$( (( MINIMAL )) && echo '（精简模式：只开 Slack）')；数据在 $DATA"
echo
echo "需要你本人做的事："
i=1
for t in "${TODO[@]}"; do echo "  $i. $t"; i=$((i + 1)); done

#!/usr/bin/env python3
"""pit 声明来源：Gmail「主要」收件箱里发给我、还没读的邮件。

通过 gws（Google Workspace 命令行）只读获取，需要本人给 gws 授权 gmail.readonly。
输出 JSON 列表，每项一封邮件，供 pit 映射成对象；读过之后它从列表里消失，对象随之结束。
"""
import glob
import json
import os
import shutil
import subprocess
import sys

QUERY = "is:unread category:primary -from:me"


def gws():
    """gws is a node script; launchd's bare PATH finds neither it nor node, so look where npm puts them."""
    extra = glob.glob(os.path.expanduser("~/.nvm/versions/node/*/bin")) + ["/opt/homebrew/bin", "/usr/local/bin"]
    path = os.pathsep.join(extra + [os.environ.get("PATH", "/usr/bin:/bin")])
    exe = shutil.which("gws", path=path)
    if not exe:
        sys.exit("找不到 gws：先运行 npm i -g @googleworkspace/cli")
    return exe, dict(os.environ, PATH=os.pathsep.join([os.path.dirname(exe), path]))


def main():
    exe, env = gws()
    p = subprocess.run([exe, "gmail", "+triage", "--max", "30", "--query", QUERY, "--format", "json"],
                       capture_output=True, text=True, timeout=60, env=env)
    try:
        data = json.loads(p.stdout or "null")
    except ValueError:
        sys.exit((p.stderr or p.stdout or "gws 没有输出")[-300:])
    if isinstance(data, dict) and data.get("error"):
        msg = str(data["error"].get("message", data["error"]))
        sys.exit("gws 没有 Gmail 只读授权（gmail.readonly）" if "insufficient" in msg.lower() else msg[-300:])
    rows = data if isinstance(data, list) else (data or {}).get("messages", [])
    out = []
    for m in rows:
        mid = m.get("id") or m.get("threadId") or m.get("messageId")
        if not mid:
            continue
        sender = (m.get("from") or m.get("sender") or "").split("<")[0].strip().strip('"') or "邮件"
        out.append({
            "key": mid,
            "title": "%s · %s" % (sender, m.get("subject") or "（无主题）"),
            "state": "未读邮件",
            "what": m.get("snippet") or m.get("date") or "",
            "link": "https://mail.google.com/mail/u/0/#inbox/%s" % (m.get("threadId") or mid),
        })
    json.dump(out, sys.stdout, ensure_ascii=False)


if __name__ == "__main__":
    main()

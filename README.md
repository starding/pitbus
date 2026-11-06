# PitBus

Mac 菜单栏里的「下一步该谁动」：PitBus 替你盯着 Slack、飞书文档评论、Google 日历、GitHub 和时间点，把每件事归到等你、等外部、已结束三个状态。Claude Code 会话可以登记自己在等什么，有动静时被叫醒，等待时不消耗 token。

安装和使用：在这个目录里打开 Claude Code，对它说「按 CLAUDE-GUIDE.md 帮我装上 PitBus」。说明里写了前提、安装、配置、日常用法和边界，人也可以直接读。

- `pit/pit.py`：常驻服务、命令行 `pit` 和 MCP 服务，只用 Python 标准库。
- `menubar/`：菜单栏应用（Swift + SwiftUI）。
- `skill/SKILL.md`：给 Claude 会话的 `pit-watch` 技能。
- `install.sh` / `uninstall.sh`：安装与卸载。
- `org/<公司>/`：某家公司自己加的渠道和规则，开源版不带。`./export-oss.sh <目录>` 导出不含 `org/` 的副本。

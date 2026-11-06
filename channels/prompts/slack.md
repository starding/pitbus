1. 检查 `slackctl auth test`。没有 slackctl 时，重新运行 PitBus 安装包里的 `./install.sh --minimal`，它会下载并校验 slackctl。
2. 没登录时，请本人先打开并登录 Slack 桌面版，再自己在终端运行 `slackctl auth import-desktop`，从桌面版导入登录状态。
3. 导入后运行 `{PIT} config`，让 PitBus 认出本人（Slack user id 和显示名）。

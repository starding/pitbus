1. 检查 `gh auth status`。没有 gh 时，告诉本人要运行 `brew install gh`（没有 Homebrew 时让本人从 cli.github.com 下载），征得同意后再装。
2. 没登录时，让本人自己在终端运行 `gh auth login`，按提示在浏览器里完成。
3. 登录后用 `gh search prs --review-requested=@me --state=open --limit 1` 试一次。

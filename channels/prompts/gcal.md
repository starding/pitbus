1. 检查 `gws auth status`。没有 gws 时，告诉本人要运行 `npm i -g @googleworkspace/cli`（需要 Node.js），征得同意后再装。
2. 没授权或没有日历权限时，让本人自己在终端运行 `gws auth login -s calendar`，在浏览器里登录公司 Google 账号并同意。gws 提示还没配置 OAuth 客户端时，把它的提示原样转告本人，由本人决定怎么处理，不要自己去建 Google Cloud 项目。
3. 授权后用 `gws calendar events list --params '{"calendarId":"primary","maxResults":1}'` 试一次，能返回就算通了。

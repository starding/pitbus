1. 检查 `gws auth status`。没有 gws 时，告诉本人要运行 `npm i -g @googleworkspace/cli`（需要 Node.js），征得同意后再装。
2. Gmail 需要只读授权 gmail.readonly。让本人自己在终端运行 `gws auth login -s gmail --readonly`，在浏览器里登录公司 Google 账号并同意。已经授权过日历的，同样要再授权一次 Gmail。
3. 授权后按最后一段启用并试运行：能列出未读邮件或空列表就算通了；报「没有 Gmail 只读授权」说明第 2 步还没完成。

1. 这个来源读 HiBob 里等本人处理的事，直接和 Bob 官方 MCP 服务通信，授权走 OAuth，令牌存在钥匙串 service=pit-bob。
2. 运行 `security find-generic-password -s pit-bob >/dev/null 2>&1 && echo 已授权` 检查，只看有没有。
3. 没有时，请本人自己在终端运行 `{PY} -I {ROOT}/channels/scripts/bob_todo.py --login`：它会打开浏览器，本人登录 Bob 并同意授权。

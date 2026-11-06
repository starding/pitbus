#!/bin/zsh
# Fake data for the README screenshot: no real people, channels or links. Then, from the repo:
#   PIT_HOME=$DIR PIT_TALL=1 PIT_OPEN=1 ~/Applications/PitBus.app/Contents/MacOS/PitBus --render-panel docs/panel-light.png
# (add `dark` at the end for docs/panel-dark.png)
set -e
export PIT_HOME=${1:?usage: docs/mock-data.sh <empty folder>}
ROOT=${0:A:h:h}
P() { python3 "$ROOT/pit/pit.py" "$@"; }
P emit slack_thread:C0MOCK0001/1800000001.000100 --state 等你回复 --level attention --source slack --app com.tinyspeck.slackmacgap \
  --title "Alex · 首页改版：周五前能给排期吗？" --text "首页改版的设计稿已经定了，研发这边周五前能给个排期吗？" --link https://example.com/slack/1
P emit github_pr:acme/web#128 --state "请你 review" --level attention --source github --app com.github.GitHubClient \
  --title "acme/web#128 支付页加 Apple Pay" --link https://github.com/acme/web/pull/128
P emit gcal:standup-1106 --state "15:00 开始" --level attention --source gcal --app com.google.Chrome \
  --title "产品评审会 · 15:00" --text "需要准备：上周数据复盘" --link https://example.com/cal/1
P emit doc_comment:mockdoc#c1 --state 评论提到你 --level attention --source lark_doc --app com.electron.lark \
  --title "Q4 路线图 · Jordan：这一项的优先级要不要调？" --link https://example.com/doc/1
P emit slack_dm:D0MOCK0002 --state 已读 --level info --source slack --app com.tinyspeck.slackmacgap \
  --title "Sam · 合同已经发给法务了" --text "合同已经发给法务了，有结果同步你" --link https://example.com/slack/2
P watch-object --session local_00000000-0000-0000-0000-000000000001 --title "合同审核" --object slack_dm:D0MOCK0002 \
  --note "Sam · 合同审核：等法务意见" --timeout 48h
P emit slack_thread:C0MOCK0003/1800000003.000300 --state 知会 --level info --source slack --app com.tinyspeck.slackmacgap \
  --title "#release · v2.4 已发布到生产环境" --link https://example.com/slack/3
P watch-slack --session local_00000000-0000-0000-0000-000000000002 --title "首页改版排期" --channel C0MOCK0001 --thread 1800000001.000100 --note "Alex · 首页改版：等排期回复"
print -r -- "好的，排期我今天下班前给你：前端 3 天，联调 1 天，下周三可以提测。" | \
  P draft-add --session local_00000000-0000-0000-0000-000000000002 --slack-channel C0MOCK0001 --thread 1800000001.000100 --note "回复 Alex 的排期问题"

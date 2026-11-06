#!/usr/bin/env python3
"""pit 声明来源：Bob（HiBob）里等我处理的事。

直接与 Bob 官方 MCP 服务（https://mcp.hibob.com/mcp/public）通信，不经过模型。
授权走 OAuth（动态注册客户端 + PKCE），令牌存在钥匙串 service=pit-bob。

  bob_todo.py --login          首次授权：打开浏览器，本人登录 Bob 并同意
  bob_todo.py --tools          列出 MCP 工具名与说明（调试用）
  bob_todo.py --call NAME JSON 调用一个只读工具并打印结果（调试用）
  bob_todo.py                  输出 JSON 列表，每项一件等我处理的事，供 pit 映射成对象

只调用 READ_TOOLS 里列出的工具，不做任何写入。
"""
import base64
import hashlib
import http.server
import json
import os
import secrets
import subprocess
import sys
import time
import urllib.parse
import urllib.request
import webbrowser

BASE = "https://mcp.hibob.com"
MCP_URL = BASE + "/mcp/public"
KEYCHAIN_SERVICE = "pit-bob"
SCOPES = "mcp:tools:read mcp:tools:execute"
PORT = 53682
# 默认的 Python-urllib User-Agent 会被 Bob 的防火墙拒绝（403）
UA = "PitBus/1.0"

# 定时拉取时允许调用的工具（只读）；--call 也只允许这些
READ_TOOLS = {
    "commons_getCurrentUserEssentials",
    "myInterviews_getMyInterviews",
    "time-off_getTimeoffPendingRequests",
    "peopleApprovals_getApprovalRequests",
    "myApprovals_getOfferApprovals",
    "myApprovals_getJobOpeningApprovals",
}


# ---------- 钥匙串 ----------

def load_creds():
    r = subprocess.run(["security", "find-generic-password", "-s", KEYCHAIN_SERVICE, "-w"],
                       capture_output=True, text=True)
    if r.returncode != 0 or not r.stdout.strip():
        return None
    return json.loads(r.stdout)


def save_creds(c):
    subprocess.run(["security", "add-generic-password", "-U", "-s", KEYCHAIN_SERVICE,
                    "-a", "pit", "-w", json.dumps(c)], check=True, capture_output=True)


# ---------- OAuth ----------

def post_form(url, data):
    req = urllib.request.Request(url, data=urllib.parse.urlencode(data).encode(),
                                 headers={"Content-Type": "application/x-www-form-urlencoded",
                                          "Accept": "application/json", "User-Agent": UA})
    with urllib.request.urlopen(req, timeout=20) as resp:
        return json.load(resp)


def post_json(url, data):
    req = urllib.request.Request(url, data=json.dumps(data).encode(),
                                 headers={"Content-Type": "application/json", "Accept": "application/json",
                                          "User-Agent": UA})
    with urllib.request.urlopen(req, timeout=20) as resp:
        return json.load(resp)


def store_tokens(c, tok):
    c["access_token"] = tok["access_token"]
    if tok.get("refresh_token"):
        c["refresh_token"] = tok["refresh_token"]
    c["expires_at"] = time.time() + int(tok.get("expires_in", 3600)) - 60
    save_creds(c)


def login():
    redirect = "http://127.0.0.1:%d/callback" % PORT
    reg = post_json(BASE + "/oauth/register", {
        "client_name": "PitBus (local)", "redirect_uris": [redirect],
        "grant_types": ["authorization_code", "refresh_token"], "response_types": ["code"],
        "token_endpoint_auth_method": "none", "scope": SCOPES,
    })
    verifier = secrets.token_urlsafe(64)
    challenge = base64.urlsafe_b64encode(hashlib.sha256(verifier.encode()).digest()).rstrip(b"=").decode()
    state = secrets.token_urlsafe(24)
    url = BASE + "/oauth/authorize?" + urllib.parse.urlencode({
        "response_type": "code", "client_id": reg["client_id"], "redirect_uri": redirect,
        "code_challenge": challenge, "code_challenge_method": "S256", "state": state,
        "scope": SCOPES, "resource": MCP_URL,
    })
    got = {}

    class Handler(http.server.BaseHTTPRequestHandler):
        def do_GET(self):
            q = urllib.parse.parse_qs(urllib.parse.urlparse(self.path).query)
            got.update({k: v[0] for k, v in q.items()})
            self.send_response(200)
            self.send_header("Content-Type", "text/html; charset=utf-8")
            self.end_headers()
            self.wfile.write("PitBus 已拿到 Bob 授权，可以关闭这个页面。".encode())

        def log_message(self, *a):
            pass

    srv = http.server.HTTPServer(("127.0.0.1", PORT), Handler)
    print("在浏览器里登录 Bob 并同意授权；没有自动打开就访问：\n" + url, flush=True)
    webbrowser.open(url)
    while "code" not in got and "error" not in got:
        srv.handle_request()
    if got.get("error") or got.get("state") != state:
        sys.exit("授权失败：%s" % (got.get("error_description") or got.get("error") or "state 不一致"))
    tok = post_form(BASE + "/oauth/token", {
        "grant_type": "authorization_code", "code": got["code"], "redirect_uri": redirect,
        "client_id": reg["client_id"], "code_verifier": verifier, "resource": MCP_URL,
    })
    store_tokens({"client_id": reg["client_id"]}, tok)
    print("已授权，令牌存入钥匙串 %s。" % KEYCHAIN_SERVICE)


def access_token():
    c = load_creds()
    if not c:
        sys.exit("还没授权 Bob：先运行 bob_todo.py --login")
    if time.time() < c.get("expires_at", 0):
        return c["access_token"]
    try:
        tok = post_form(BASE + "/oauth/token", {
            "grant_type": "refresh_token", "refresh_token": c["refresh_token"],
            "client_id": c["client_id"], "resource": MCP_URL,
        })
    except urllib.error.HTTPError as e:
        sys.exit("Bob 授权已失效（%s），重新运行 bob_todo.py --login" % e.code)
    store_tokens(c, tok)
    return c["access_token"]


# ---------- MCP ----------

class MCP:
    def __init__(self, token):
        self.token, self.session, self.n = token, None, 0
        self.rpc("initialize", {"protocolVersion": "2025-06-18", "capabilities": {},
                                "clientInfo": {"name": "pitbus", "version": "1"}})
        self.rpc("notifications/initialized", None, notify=True)

    def rpc(self, method, params, notify=False):
        body = {"jsonrpc": "2.0", "method": method}
        if params is not None:
            body["params"] = params
        if not notify:
            self.n += 1
            body["id"] = self.n
        h = {"Authorization": "Bearer " + self.token, "Content-Type": "application/json",
             "Accept": "application/json, text/event-stream", "User-Agent": UA}
        if self.session:
            h["Mcp-Session-Id"] = self.session
        req = urllib.request.Request(MCP_URL, data=json.dumps(body).encode(), headers=h)
        with urllib.request.urlopen(req, timeout=60) as resp:
            self.session = resp.headers.get("Mcp-Session-Id") or self.session
            raw = resp.read().decode()
            ctype = resp.headers.get("Content-Type", "")
        if notify or not raw.strip():
            return None
        if "text/event-stream" in ctype:
            msgs = [json.loads(l[5:]) for l in raw.splitlines() if l.startswith("data:") and l[5:].strip()]
            msg = next(m for m in msgs if m.get("id") == body["id"])
        else:
            msg = json.loads(raw)
        if "error" in msg:
            raise RuntimeError("%s: %s" % (method, msg["error"]))
        return msg["result"]

    def tools(self):
        out, cursor = [], None
        while True:
            r = self.rpc("tools/list", {"cursor": cursor} if cursor else {})
            out += r.get("tools", [])
            cursor = r.get("nextCursor")
            if not cursor:
                return out

    def call(self, name, args):
        if name not in READ_TOOLS:
            sys.exit("%s 不在只读白名单里" % name)
        r = self.rpc("tools/call", {"name": name, "arguments": args})
        if r.get("structuredContent") is not None:
            return r["structuredContent"]
        text = "".join(c.get("text", "") for c in r.get("content", []) if c.get("type") == "text")
        try:
            return json.loads(text)
        except ValueError:
            return text


# 原始记录留一份，字段名以真实数据为准再调映射
SAMPLES = os.path.expanduser("~/Library/Application Support/pit/bob_samples.json")
APP = "https://app.hibob.com"


def flat(rec, prefix=""):
    """{"a": {"b": 1}} -> {"a.b": 1}，键统一小写，便于按候选名取值。"""
    out = {}
    for k, v in (rec.items() if isinstance(rec, dict) else []):
        key = (prefix + "." + k if prefix else k).lower()
        if isinstance(v, dict):
            out.update(flat(v, key))
        else:
            out[key] = v
    return out


def pick(f, *names):
    """按候选字段名（完整路径或末段）取第一个非空值。"""
    for n in names:
        for k, v in f.items():
            if (k == n or k.endswith("." + n)) and v not in (None, "", []):
                return v if not isinstance(v, list) else ", ".join(str(x) for x in v)
    return ""


def rows(r):
    if isinstance(r, list):
        return r
    if isinstance(r, dict):
        for k in ("data", "items", "requests", "results"):
            if isinstance(r.get(k), list):
                return r[k]
    return []


def todos(m):
    me = m.call("commons_getCurrentUserEssentials", {})
    my_name = me.get("displayName", "")
    raw, out = {}, []

    def add(key, title, state, what, link):
        out.append({"key": key, "title": title, "state": state, "what": what, "link": link or APP})

    # 面试：面评待写或逾期；排期中的面试
    r = rows(m.call("myInterviews_getMyInterviews", {"type": "hiring_my_interviews", "configuration": {}}))
    raw["interviews"] = r
    for x in r:
        f = flat(x)
        ev = str(pick(f, "evaluationstatus", "evaluation.status")).lower()
        st = str(pick(f, "status", "interviewstatus")).lower()
        if ev in ("pending", "overdue") and st in ("taken_place", "completed"):
            state = "面评逾期" if ev == "overdue" else "待写面评"
        elif st == "scheduled":
            state = "待面试"
        else:
            continue
        add("interview:%s" % pick(f, "id", "interviewid"),
            "面试 · %s · %s" % (pick(f, "candidatename", "candidate.name", "candidate"),
                               pick(f, "jobopeningtitle", "jobtitle", "job.title")),
            state, "时间 %s；面评截止 %s" % (pick(f, "date", "datetime", "starttime"),
                                          pick(f, "evaluationduedate", "duedate") or "—"), "")

    # Offer 与职位审批：待审批且当前处理人是我
    for tool, typ, label in (("myApprovals_getOfferApprovals", "hiring_offer_approvals", "Offer 审批"),
                             ("myApprovals_getJobOpeningApprovals", "hiring_job_opening_approvals", "职位审批")):
        r = rows(m.call(tool, {"type": typ, "configuration": {}}))
        raw[tool] = r
        for x in r:
            f = flat(x)
            status = str(pick(f, "status", "approvalstatus")).lower()
            assignee = str(pick(f, "currentassignee", "currentapprover", "assignee"))
            if "pending" not in status or (assignee and my_name.split(" ")[0] not in assignee):
                continue
            add("%s:%s" % (typ, pick(f, "id", "approvalid", "externalid")),
                "%s · %s" % (label, pick(f, "candidatename", "jobtitle", "title")),
                "等你审批", "申请人 %s" % pick(f, "requester", "requestedby", "requestor"), "")

    # 假期：等我批的
    r = rows(m.call("time-off_getTimeoffPendingRequests", {}))
    raw["timeoff"] = r
    for x in r:
        f = flat(x)
        if pick(f, "isforaction") is False:
            continue
        add("timeoff:%s" % pick(f, "id", "requestid"),
            "假期审批 · %s" % pick(f, "employeedisplayname", "displayname", "employeename", "employee"),
            "等你审批", "%s %s ~ %s" % (pick(f, "policytypedisplayname", "policytype", "type"),
                                    pick(f, "startdate", "start"), pick(f, "enddate", "end")),
            APP + "/time-off")

    # 人事审批：进行中的，只留下一位审批人是我的
    r = rows(m.call("peopleApprovals_getApprovalRequests",
                    {"statusList": ["Open", "PendingResubmission"], "requestedForFilter": []}))
    raw["people"] = r
    for x in r:
        f = flat(x)
        if str(pick(f, "nextapprover", "nextapproverid")) not in (me.get("id"), my_name):
            continue
        add("people:%s" % pick(f, "id", "requestid"), "人事审批 · %s" % pick(f, "flowtype", "type", "name"),
            "等你审批", "状态 %s" % pick(f, "status"), "")

    if any(raw.values()):
        with open(SAMPLES, "w") as fp:
            json.dump(raw, fp, ensure_ascii=False, indent=1)
    return out


def main():
    if "--login" in sys.argv:
        return login()
    m = MCP(access_token())
    if "--tools" in sys.argv:
        for t in m.tools():
            ann = t.get("annotations") or {}
            print("%s\t%s\t%s" % (t["name"], "ro" if ann.get("readOnlyHint") else "-",
                                  (t.get("description") or "").split("\n")[0][:120]))
        return
    if "--call" in sys.argv:
        i = sys.argv.index("--call")
        print(json.dumps(m.call(sys.argv[i + 1], json.loads(sys.argv[i + 2]) if len(sys.argv) > i + 2 else {}),
                         ensure_ascii=False, indent=1)[:6000])
        return
    json.dump(todos(m), sys.stdout, ensure_ascii=False)


if __name__ == "__main__":
    main()

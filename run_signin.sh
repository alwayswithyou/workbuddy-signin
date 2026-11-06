#!/usr/bin/env bash
# WorkBuddy / CodeBuddy 每日签到包装脚本
# - 在 7:00-8:00 之间随机时间执行（cron 7:00 触发，本脚本随机延时 0~3600s）
# - 兜底：令牌过期前置检查 + 签到结果鉴权失败检测，提示重新登录并写标记文件
# - 通知：签到成功/失败均通过企业微信群机器人 Webhook 推送（见 wecom.conf）
set -u

WORKDIR=/home/tangyanjie/CodeBuddy/20260731190757
LOG="$WORKDIR/signin-cron.log"
AUTH="$HOME/.local/share/CodeBuddyExtension/Data/Public/auth/Tencent-Cloud.coding-copilot.info"
FLAG="$WORKDIR/.token-expired.flag"
PY=/usr/bin/python3

cd "$WORKDIR" || exit 1

ts() { date '+%F %T'; }

# 企业微信通知（失败不影响主流程；任何时候都不应改变签到任务退出码）
notify() { "$PY" wecom_notify.py "$1" "$2" >> "$LOG" 2>&1 || true; }

# 1) 随机延时 0~3600 秒，使实际执行落在 7:00-8:00 窗口
DELAY=$(( RANDOM % 3600 ))
echo "$(ts) [wrap] 随机延时 ${DELAY}s 后执行签到" >> "$LOG"
sleep "$DELAY"

# 2) 令牌过期前置检查（expiresAt 为毫秒）
EXP=$("$PY" - "$AUTH" <<'PY'
import json, sys
try:
    d = json.load(open(sys.argv[1]))
    exp = d.get("auth", {}).get("expiresAt")
    print(int(exp) if isinstance(exp, (int, float)) else 0)
except Exception:
    print(-1)
PY
)
NOW_MS=$("$PY" -c "import time;print(int(time.time()*1000))")
if [ "$EXP" -gt 0 ] && [ "$NOW_MS" -ge $((EXP - 300000)) ]; then
  MSG="⚠️ 令牌已过期或即将过期（exp_ms=$EXP），请运行 \`codebuddy\` 重新登录，令牌将自动刷新后恢复签到。"
  echo "$(ts) [wrap] $MSG" >> "$LOG"
  echo "EXPIRED exp_ms=$EXP now_ms=$NOW_MS" > "$FLAG"
  notify "❌ WorkBuddy 签到失败" "$MSG"
  command -v notify-send >/dev/null 2>&1 && DISPLAY=:0 notify-send "WorkBuddy 签到" "令牌已过期，请运行 codebuddy 重新登录" 2>/dev/null
  exit 0
fi

# 3) 执行签到
OUT=$("$PY" signin.py auto 2>&1)
echo "$OUT" >> "$LOG"

# 4) 解析结果：判定成功/鉴权失败，并构造通知内容
PARSED=$("$PY" - "$OUT" <<'PY'
import sys, json
txt = sys.argv[1]
lines = [l for l in txt.splitlines() if l.strip().startswith("{")]
last = lines[-1] if lines else "{}"
try:
    d = json.loads(last)
except Exception:
    print("PARSE_FAIL")
    print("无法解析签到输出，请检查 signin-cron.log。")
    sys.exit(0)
r = d.get("result", "")
authfail = (r in ("AUTH_REJECTED", "FORBIDDEN", "AUTH_ERROR", "NO_AUTH",
                  "NO_SESSION", "UNSUPPORTED_ENVELOPE")
            or ("http" in d and int(d.get("http", 200)) in (401, 403)))
if authfail:
    print("AUTH_FAIL")
    print("⚠️ 签到返回鉴权失败（result=%s）。请运行 `codebuddy` 重新登录后再试。" % r)
else:
    print("OK")
    rep = d.get("report", "")
    growth = d.get("growth", "")
    lines = []
    if d.get("today_credit") is not None:
        lines.append("🎯 本次签到获取：+%s 积分" % d.get("today_credit"))
    if d.get("streak_days") is not None:
        lines.append("🔥 连续签到：%s 天" % d.get("streak_days"))
    if rep:
        lines.append("📋 签到详情：" + rep)
    if growth:
        lines.append("🐱 派猫猫出行 / 成长中心：" + growth)
    print("\n".join(lines))
PY
)
RES=$(echo "$PARSED" | head -1)
CONTENT=$(echo "$PARSED" | tail -n +2)

if [ "$RES" = "AUTH_FAIL" ]; then
  echo "$(ts) [wrap] 签到返回鉴权失败，请运行 'codebuddy' 重新登录后再试。" >> "$LOG"
  echo "AUTH_FAIL $(ts)" > "$FLAG"
  notify "❌ WorkBuddy 签到失败" "$CONTENT"
  command -v notify-send >/dev/null 2>&1 && DISPLAY=:0 notify-send "WorkBuddy 签到" "鉴权失败，请运行 codebuddy 重新登录" 2>/dev/null
else
  rm -f "$FLAG"
  # 账户总剩余积分 + 临期积分（来自计费接口，独立于签到累计的 total_credits）
  BAL=$("$PY" - "$AUTH" <<'PY'
import json, sys, time, ssl, urllib.request
def post(url, headers):
    req = urllib.request.Request(url, data=b"{}", headers=headers, method="POST")
    with urllib.request.urlopen(req, timeout=10, context=ssl.create_default_context()) as r:
        return json.loads(r.read().decode("utf-8"))
try:
    d = json.load(open(sys.argv[1]))
    tok = d["auth"]["accessToken"]; uid = d["account"]["uid"]
    ent = d["account"].get("enterpriseId"); dom = d["auth"].get("domain")
    H = {"Accept": "application/json", "Authorization": "Bearer %s" % tok,
         "Content-Type": "application/json", "X-User-Id": uid, "User-Agent": "WorkBuddy"}
    if ent: H["X-Enterprise-Id"] = ent; H["X-Tenant-Id"] = ent
    if dom: H["X-Domain"] = dom
    ep = d["auth"].get("endpoint") or "https://copilot.tencent.com"
    if not ep.startswith("http"): ep = "https://" + ep
    summ = post(ep + "/billing/meter/get-user-resource-summary", H)
    total = 0.0
    for p in summ.get("data", {}).get("Packages", []):
        try: total += float(p.get("CycleRemainCapacity") or 0)
        except Exception: pass
    res = post(ep + "/billing/meter/get-user-resource", H)
    accounts = res.get("data", {}).get("Response", {}).get("Data", {}).get("Accounts", [])
    now = time.time() * 1000.0
    e7 = e30 = 0.0
    for a in accounts:
        et = a.get("CycleEndTime")
        if not et: continue
        try:
            t = time.mktime(time.strptime(et, "%Y-%m-%d %H:%M:%S")) * 1000
        except Exception:
            continue
        days = (t - now) / 86400000.0
        if days < 0: days = 0
        rem = 0.0
        for k in ("CycleCapacityRemainPrecise", "CycleCapacityRemain",
                  "CapacityRemainPrecise", "CapacityRemain"):
            v = a.get(k)
            if v is not None:
                try: rem = float(v); break
                except Exception: pass
        if days <= 7: e7 += rem
        if days <= 30: e30 += rem
    print("BAL")
    print("%.2f|%.2f|%.2f" % (total, e7, e30))
except Exception as e:
    print("BAL_FAIL")
    print("余额查询失败：%s" % e)
PY
  )
  BRES=$(echo "$BAL" | head -1)
  if [ "$BRES" = "BAL" ]; then
    BDATA=$(echo "$BAL" | tail -n +2 | head -1)
    IFS='|' read -r BTOT BE7 BE30 <<< "$BDATA"
    CONTENT="${CONTENT}
💰 账户总剩余积分：${BTOT}
⏳ 临期积分：7天内到期 ${BE7} / 30天内到期 ${BE30}（请尽快使用）"
  else
    echo "$(ts) [wrap] 余额查询失败：$BAL" >> "$LOG"
  fi
  notify "✅ WorkBuddy 签到成功" "$CONTENT"
fi

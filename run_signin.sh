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
    if d.get("total_credits") is not None:
        lines.append("💰 当前总积分：%s" % d.get("total_credits"))
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
  notify "✅ WorkBuddy 签到成功" "$CONTENT"
fi

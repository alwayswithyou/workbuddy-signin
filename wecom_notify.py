#!/usr/bin/env python3
"""企业微信「应用」消息推送（text 纯文本，便于在个人微信中完整显示）。

配置：同目录下 wecom.conf 写入
    QYWX_AM=corpid,corpsecret,touser,agentid
其中：
  corpid    : 企业 ID
  corpsecret: 应用 Secret
  touser    : 接收人 userid，@all 表示应用可见范围内所有人
  agentid   : 应用 ID
（若附带第 5 个字段，本脚本会忽略，不影响官方接口推送）

未配置时自动跳过（打印 WECOM_SKIP），不影响签到主流程。
"""
import sys
import json
import os
import urllib.request
import urllib.parse

CONF = os.path.join(os.path.dirname(os.path.abspath(__file__)), "wecom.conf")
GET_TOKEN = "https://qyapi.weixin.qq.com/cgi-bin/gettoken?corpid={corpid}&corpsecret={secret}"
SEND_MSG = "https://qyapi.weixin.qq.com/cgi-bin/message/send?access_token={token}"


def load_am():
    raw = ""
    try:
        with open(CONF, encoding="utf-8") as f:
            for line in f:
                line = line.strip()
                if not line or line.startswith("#") or "=" not in line:
                    continue
                k, v = line.split("=", 1)
                if k.strip() == "QYWX_AM":
                    raw = v.strip().strip('"').strip("'")
    except Exception:
        pass
    return raw


def _plain(s):
    """去掉 markdown 标记，便于在个人微信中完整显示。"""
    import re
    s = re.sub(r"\*\*(.+?)\*\*", r"\1", s)        # 粗体
    s = re.sub(r"^#+\s*", "", s, flags=re.M)       # 标题
    s = re.sub(r"^>\s?", "", s, flags=re.M)        # 引用
    s = s.replace("`", "")                          # 行内代码
    return s.strip()


def get_token(corpid, secret):
    url = GET_TOKEN.format(
        corpid=urllib.parse.quote(corpid), secret=urllib.parse.quote(secret)
    )
    req = urllib.request.Request(url)
    with urllib.request.urlopen(req, timeout=10) as r:
        return json.loads(r.read().decode("utf-8"))


def send(title, content):
    am = load_am()
    if not am:
        print("WECOM_SKIP: 未配置 QYWX_AM，跳过企业微信通知")
        return 1
    parts = [p.strip() for p in am.split(",")]
    if len(parts) < 4:
        print("WECOM_ERR: QYWX_AM 字段不足，需 corpid,corpsecret,touser,agentid")
        return 1
    corpid, secret, touser, agentid = parts[0], parts[1], parts[2], parts[3]
    try:
        agentid = int(agentid)
    except Exception:
        pass

    try:
        tok = get_token(corpid, secret)
    except Exception as e:  # noqa: BLE001
        print("WECOM_ERR token:", e)
        return 1
    if tok.get("errcode", 0) != 0:
        print("WECOM_ERR token:", tok)
        return 1

    url = SEND_MSG.format(token=tok["access_token"])
    body = {
        "touser": touser,
        "msgtype": "text",
        "agentid": agentid,
        "text": {"content": "%s\n\n%s" % (_plain(title), _plain(content))},
    }
    data = json.dumps(body, ensure_ascii=False).encode("utf-8")
    req = urllib.request.Request(
        url, data=data, headers={"Content-Type": "application/json"}
    )
    try:
        with urllib.request.urlopen(req, timeout=10) as r:
            resp = json.loads(r.read().decode("utf-8"))
        print("WECOM_RESP:", resp)
        return 0 if resp.get("errcode") == 0 else 1
    except Exception as e:  # noqa: BLE001
        print("WECOM_ERR send:", e)
        return 1


if __name__ == "__main__":
    if len(sys.argv) < 3:
        print("usage: wecom_notify.py <title> <content>")
        sys.exit(2)
    sys.exit(send(sys.argv[1], sys.argv[2]))

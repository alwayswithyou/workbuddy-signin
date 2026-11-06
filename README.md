# WorkBuddy / CodeBuddy 每日自动签到 + 企业微信通知

基于 [88lin/workbuddy-auto-signin](https://github.com/88lin/workbuddy-auto-signin) 的 `signin.py`，
在本机 **CodeBuddy CLI** 登录态上实现 WorkBuddy 每日自动签到，并通过**企业微信「应用」消息**把
成功/失败结果推送到你的企业微信（可转发到个人微信）。

> 说明：`signin.py` 为非官方、逆向自 WorkBuddy 桌面端的脚本，腾讯改版可能随时失效，请自担服务条款风险。

---

## 功能特性

- ✅ 复用本机 CodeBuddy CLI 的明文登录态，无需 WorkBuddy 桌面端
- ⏰ 每天 **7:00 触发、7:00–8:00 之间随机时刻**执行（避免整点集中请求）
- 🛡️ **令牌过期兜底**：前置检查凭据 `expiresAt` + 结果鉴权码判定，失败写标记并提示重登
- 🔔 **企业微信应用推送**：签到成功 / 失败都会收到通知
- 💰 **账户真实余额**：通过计费接口（`get-user-resource-summary` / `get-user-resource`）取「账户总剩余积分」，并提示 **近期临期积分**（7 天内 / 30 天内到期多少），而非签到累计积分
- 📱 推送为 `text` 纯文本，便于在个人微信中完整显示（含 emoji）
- 🔁 支持手动即时运行与 cron 定时运行

---

## 文件说明

| 文件 | 作用 |
|---|---|
| `signin.py` | 上游签到主脚本（来自 88lin/workbuddy-auto-signin，已随本仓库打包） |
| `run_signin.sh` | 包装脚本：随机延时、令牌过期兜底、解析结果、触发通知、写标记 |
| `wecom_notify.py` | 企业微信「应用」消息推送（取 access_token 后发送 text 消息） |
| `wecom.conf` | **你的真实凭据**（不入库，需自行创建，格式见下方） |
| `wecom.conf.example` | 凭据模板，复制为 `wecom.conf` 后填值 |

---

## 前置要求

- **Linux / macOS / Windows**（本方案在 Linux 上验证）
- **Python 3**（仅用标准库，无需 pip 安装）
- **CodeBuddy CLI** 已安装并登录（会写出明文凭据）
- **企业微信自建应用** + 一个接收人 userid（用于推送）

### 1. 安装并登录 CodeBuddy CLI

```bash
# 方式一：npm 全局安装
npm install -g @tencent-ai/codebuddy-code

# 方式二：原生安装器（Beta，无需 Node.js）
curl -fsSL https://copilot.tencent.com/cli/install.sh | bash
```

安装后登录一次（终端会写出明文凭据）：

```bash
codebuddy login        # 按提示扫码 / 授权
codebuddy whoami       # 确认已登录
```

登录后，Linux 上的明文凭据通常位于：

```
~/.local/share/CodeBuddyExtension/Data/Public/auth/Tencent-Cloud.coding-copilot.info
```

> 若路径不同，请修改 `run_signin.sh` 中的 `AUTH` 变量。

### 2. 准备 signin.py

本仓库已打包 `signin.py`，可直接使用。如需更新到最新版：

```bash
# GitHub 直连（部分地区可能不可达）
curl -fsSL https://raw.githubusercontent.com/88lin/workbuddy-auto-signin/main/signin.py -o signin.py

# 或用 jsDelivr CDN 镜像
curl -fsSL https://cdn.jsdelivr.net/gh/88lin/workbuddy-auto-signin@main/signin.py -o signin.py
```

先用 `doctor` 离线校验能否探测到登录态：

```bash
python3 signin.py doctor      # 期望看到 AUTH_READY / plaintext
python3 signin.py status      # 联网只读查询，期望 HTTP 200
```

### 3. 配置企业微信应用推送

前往企业微信管理后台 → 应用管理 → 自建应用，拿到 `corpid / corpsecret / agentid`，
以及接收人 `userid`（在「通讯录」里查看）。然后在仓库目录：

```bash
cp wecom.conf.example wecom.conf
```

编辑 `wecom.conf`，填入真实值（**一行，逗号分隔，无空格**）：

```ini
QYWX_AM=你的corpid,你的corpsecret,你的userid,你的agentid
```

- `touser` 设为 `@all` 可推送给应用可见范围内所有人；设为具体 `userid` 只推给该人
- 末尾附带的第 5 个字段会被脚本忽略，不影响官方接口

### 4. 安装定时任务（cron）

```bash
chmod +x run_signin.sh wecom_notify.py
crontab -e
# 加入下面一行（每天 7:00 触发，脚本内随机延时 0~3600s，落在 7–8 点）：
0 7 * * * /绝对路径/workbuddy-signin/run_signin.sh
```

> 请把路径换成你实际的仓库绝对路径。日志写入同目录 `signin-cron.log`。

---

## 使用说明

手动运行（调试 / 即时签到）：

```bash
bash run_signin.sh                 # 走完整包装流程（随机延时 + 通知）

python3 signin.py status          # 仅查询签到状态
python3 signin.py auto            # 仅签到 + 领奖（不通知）
python3 wecom_notify.py "标题" "正文"   # 单独测试推送
```

查看运行结果：

```bash
tail -f signin-cron.log           # 实时日志
cat .token-expired.flag           # 若文件存在，说明令牌已过期需重登
```

令牌过期后，只需在终端运行一次 `codebuddy` 重新登录，次日 cron 会自动读到新令牌恢复签到。

---

## 通知消息示例

**签到成功：**

```
✅ WorkBuddy 签到成功

🎯 本次签到获取：+100 积分
🔥 连续签到：25 天
💰 账户总剩余积分：3733.64
⏳ 临期积分：7天内到期 419.64 / 30天内到期 3733.64（请尽快使用）
📋 签到详情：今日已签过（今日 +100，连续 25 天，累计 2500 积分）
🐱 派猫猫出行 / 成长中心：Buddy 旅行中（咖啡馆，约 46 分钟后回）；……
```

> 说明：消息头条的「账户总剩余积分」来自计费接口 `get-user-resource-summary`
> （各积分包 `CycleRemainCapacity` 之和，与 App 顶部「剩余积分」一致），
> 而「签到详情」里的「累计 2500 积分」是签到活动累计值，两者口径不同。
> 「临期积分」按各积分包 `CycleEndTime` 距今天数汇总（7 天 / 30 天窗口）。

**签到失败（令牌过期 / 鉴权失败）：**

```
❌ WorkBuddy 签到失败

⚠️ 令牌已过期或即将过期（exp_ms=...），请运行 `codebuddy` 重新登录，令牌将自动刷新后恢复签到。
```

> 领奖日消息会自动带上「派猫猫出行 / 任务 / 盲盒 获得 +creditXX」的具体数字；未领奖日只显示旅行状态。

---

## 在个人微信接收

推送目标是**企业微信应用**，要在个人微信里收到需打开转发开关：

**企业微信 App** → 我 → 设置 → 新消息通知 → 开启「**在微信中接收企业微信消息**」

（或在个人微信：通讯录 → 企业微信联系人/我的企业 → 开启接收企业消息）

开启后，发给你的应用消息会同步到个人微信。建议消息用 `text` 而非 `markdown`，个人微信显示最稳定。

---

## 兜底与失效处理

- **前置检查**：脚本读取凭据 `expiresAt`（毫秒，约 30 天有效期），若已过期或 5 分钟内将过期，
  跳过签到、写 `.token-expired.flag`、推送失败通知。
- **结果检查**：解析 `signin.py` 返回 `result`，命中以下任一即判定需重登并通知：
  `AUTH_REJECTED / FORBIDDEN / AUTH_ERROR / NO_AUTH / NO_SESSION / UNSUPPORTED_ENVELOPE`，
  或 HTTP 401 / 403。
- 兜底只能**检测并提醒**，无法在无界面 cron 下自动完成扫码登录；重登后次日自动恢复。

---

## 安全与免责

- `wecom.conf` 含企业微信 `corpsecret`，已被 `.gitignore` 忽略，**请勿提交到任何公开仓库**。
- 本方案仅调用腾讯公开 API，不内置任何密钥；所有凭据均在你本机。
- `signin.py` 为非官方逆向脚本，依赖 WorkBuddy 接口，可能随官方改版失效。
- 请遵守企业微信 / 腾讯相关服务条款，仅用于个人自动化签到。

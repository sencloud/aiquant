---
name: backend-deploy
description: 更新喜宽线上服务端（47.110.227.73:/server）的流程：交叉编译 linux 二进制、部署脚本、systemd 重启、nginx 配置、数据库迁移与定时任务。改后端代码/配置后要上线，或排查线上服务问题时使用。
metadata:
  short-description: 后端上线流程与线上陷阱
---

# 后端部署

线上是一台机器三个 systemd unit，**共用同一个二进制** `/server/bin/finme-server`：

```
finme-api        finme-server api       --config /server/config/config.toml   (127.0.0.1:8080，nginx 反代)
finme-scheduler  finme-server scheduler --config /server/config/config.toml   (定时任务)
finme-pusher     finme-server pusher    --config /server/config/config.toml   (推送)
```

所以换二进制后**三个都必须重启**，否则会有进程继续跑旧代码。

## 标准流程

```powershell
# 1) 在 WSL Ubuntu 里交叉编译 linux/amd64（产物 .tools/_build/finme-server，已 gitignore）
wsl -d Ubuntu -e bash /mnt/d/GitHub/aiquant/.tools/build_linux.sh

# 2) scp 上去 → 校验 sha256 → 备份旧二进制 → 换新 → 重启三个 unit → health 探测
powershell -File .\.tools\deploy.ps1
```

部署脚本自己会做 sha 校验、备份到 `/server/backup/bin/`、`systemctl restart` 三个 unit 并打 health。跑完要确认输出里 `remote sha256` 和本地一致、三个 unit 都是 `active (running)`。

验证不要只看单元状态，要打真实接口：健康检查是 `/healthz`（`/v1/health` 返回 404；deploy.ps1 会先试前者再退回后者，手工验证直接用 `/healthz`）。

## 部署凭据（不入库）

`deploy.ps1` 里**不再写任何密码**。凭据按以下顺序取，逐项第一个非空值生效：

1. 脚本参数：`-TargetHost` / `-User` / `-KeyFile` / `-Hostkey` / `-UseAgent`
2. 环境变量：`AIQUANT_DEPLOY_HOST`、`AIQUANT_DEPLOY_USER`、`AIQUANT_DEPLOY_PASSWORD`、`AIQUANT_DEPLOY_KEYFILE`、`AIQUANT_DEPLOY_HOSTKEY`
3. `.tools/deploy.local.ps1`（已 gitignore，被 dot-source，设置 `$DeployHost` / `$DeployUser` / `$DeployPassword` / `$DeployKeyFile` / `$DeployHostkey`）
4. `.tools/deploy.local.json`（已 gitignore，字段 `host` / `user` / `password` / `keyFile` / `hostkey`）
5. 脚本内置的非敏感默认值（主机、用户、host key 指纹）

一个凭据都没配时脚本直接报错退出，并列出上面几种配置方式。

首次配置：

```powershell
Copy-Item .tools\deploy.local.example.ps1 .tools\deploy.local.ps1
# 编辑 .tools\deploy.local.ps1，填 $DeployKeyFile（推荐）或 $DeployPassword
git status --ignored .tools   # 确认 deploy.local.ps1 显示为 ignored，不会被提交
```

**推荐改用 SSH 密钥登录**：plink/pscp 只认 PuTTY 的 `.ppk`。用 `puttygen` 生成密钥（或用 `ssh-keygen` 生成后在 puttygen 里导入转换），把公钥追加到服务器 `~/.ssh/authorized_keys`，在本地文件里设 `$DeployKeyFile = 'C:\path\to\deploy.ppk'`（或设环境变量 `AIQUANT_DEPLOY_KEYFILE`）。确认密钥能登录后，把 `$DeployPassword` 清空，并在服务器 `sshd_config` 里关掉密码登录（`PasswordAuthentication no`）。也可以把密钥加载到 Pageant，然后用 `-UseAgent` 运行。

用密码时，脚本通过 `-pwfile`（临时文件，用完即删）传给 plink/pscp，不会出现在命令行和进程列表里。

**禁止**：把密码、私钥、`deploy.local.*` 写进任何提交、文档、聊天或日志。仓库是公开的。

## 必须知道的三件事

**1. deploy.ps1 打的是当前工作区，不是 git 提交。** 有未提交的改动会被一起发上线。发之前先 `git status`，把不该上的 WIP 排除掉（或先提交）。仓库里其他人的半成品混进去，是最容易出事的点。

**2. 迁移是启动时自动跑的。** `internal/store/migrations/NNNN_*.sql` 按文件名排序执行，跑过的记在 `schema_migrations` 表里。因此：新增文件即生效（下次重启执行）；**修改或删除已执行过的文件不会重跑**，要改结构只能再加一个迁移。api 和 scheduler 都会跑，先启动的那个执行。

**3. 配置改动只有重启才生效。** `/server/config/config.toml` 是 `LoadConfig` 启动时读一次；`applyEnv` 只覆盖少数几项（`FINME_LLM__*`、`FINME_APPLE*`、`FINME_AI__HOME_SUGGEST_ENABLED` 等）。改配置的流程是：备份 → 改 → `systemctl restart` 相关 unit → 验证。

## nginx 不在这套脚本里，要单独改

配置文件：`/etc/nginx/sites-available/api.singzquant.com.conf`（nginx 1.18）。改动流程：备份到 `/server/backup/nginx/` → 改 → `nginx -t` → `systemctl reload nginx`。

要点：

- 全局 `client_max_body_size 1m`。任何接受大 body 的接口（图片 base64、截图上传）必须在自己的 `location` 里放宽，否则客户端会收到 413，而**后端日志里什么都看不到**——很容易误判成后端 bug。`/v1/ai/chat` 现在是 `24m`，`/v1/portfolio/parse-screenshot` 是 `12m`。
- `/v1/ai/chat` 是 SSE，`location` 里必须保持 `proxy_buffering off` / `proxy_read_timeout ≥ 300s`，别被通用配置覆盖。
- 验证 body 上限有没有生效：用一个超过旧上限的请求打过去，期望是业务错误（如 401）而不是 413。

## 定时任务

定时任务都在 **scheduler 进程**里，入口是 `cmd/finme-server/main.go` 的 `runScheduler`。新增一个 `scheduler.Job`（`Name/Interval/Run`）后必须在那里 `sch.Register(...)`，否则只是死代码。

`Scheduler.runJob` 在**启动时立刻跑一次**再进 ticker，所以重启 scheduler 就是触发一次任务的快捷方式。任务要自己保证幂等（例如 `ai_home_suggestions` 用 `<date>:<phase>` 唯一键）。

日志不在 journalctl：unit 用 `StandardOutput=append:/server/logs/*.log`，查日志看 `/server/logs/api.log`、`scheduler.log`。`journalctl -u` 只有 systemd 自己的启停记录。

## 本地验证（省钱又省事）

部署前可以用一份临时配置在 Windows 本地把服务跑起来验证，不必先上生产：`go build` 出 exe，用环境变量注入 `FINME_ENV=dev`、三个 `FINME_SECURITY__*`（必须是合法 base64 的 32 字节，随便写的短串会在 validate 阶段直接启动失败）、`FINME_DB__PATH`（指向临时库）、`FINME_SERVER__LISTEN`，然后 `finme-server.exe api --config=`（空字符串 = 不读 toml，纯用默认值 + 环境变量）。dev 模式才有 `/v1/credits/dev/topup`，mock 邮箱验证码会打到 stdout。

## 两个容易自伤的坑

- **不要对仓库里的 Go 文件跑 `gofmt -w`**：工作区是 CRLF，gofmt 会整文件重写成 LF，diff 从几行变成几百行。只有新写的文件才需要格式化。
- 别把 `backend/config/config.toml`、`/server/secrets/*` 里的真实密钥带进提交或日志。

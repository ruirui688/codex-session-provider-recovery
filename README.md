# Codex Session Provider Recovery

切换 Codex 登录方式、账号、模型供应商或本地代理后，旧聊天记录可能突然不显示。  
这个仓库提供一个简单教程和 PowerShell 脚本，用来恢复本地 Codex 桌面端旧会话列表。

> 适用于 Windows 上的 Codex 桌面端。本工具只处理本机 `C:\Users\<你>\.codex` 下的本地会话索引，不会恢复云端删除的数据。

English summary: recover missing local Codex Desktop chat history after changing login method, account, model provider, OpenAI-compatible proxy, or `model_provider`.

## Search keywords

如果你是通过搜索找到这里，常见问题一般会这样描述：

- Codex 切换账号后聊天记录消失
- Codex 更换登录方式后旧对话不见
- Codex Desktop old conversations disappeared
- Codex missing chat history after login change
- Codex sessions not showing after provider change
- Codex `model_provider` changed from `OpenAI` to `codexproxy_codex`
- recover `.codex\sessions` and `state_5.sqlite`

## 什么时候用

如果你遇到这些现象，可以尝试：

- 左侧项目还在，但下面显示“暂无对话”
- 只能看到切换账号/供应商之后的新对话
- 搜索旧标题找不到
- `C:\Users\<你>\.codex\sessions` 里还存在很多旧 `rollout-*.jsonl`
- `C:\Users\<你>\.codex\state_5.sqlite` 里还能查到旧线程

常见原因：旧会话记录里的 `model_provider` 还是旧值，例如 `OpenAI`，而当前 Codex 使用了新的 provider，例如 `codexproxy_codex`。桌面端列表会按当前 provider 过滤，导致旧记录“看起来丢了”。

## 快速修复

先关闭 Codex 桌面端更稳。然后打开 PowerShell：

```powershell
git clone git@github.com:ruirui688/codex-session-provider-recovery.git
cd codex-session-provider-recovery
```

先只检查，不修改：

```powershell
.\scripts\recover-codex-sessions.ps1
```

确认输出里能看到旧 provider 后，再执行恢复：

```powershell
.\scripts\recover-codex-sessions.ps1 -Apply
```

恢复后重新打开 Codex，搜索旧会话关键词，例如项目名、聊天标题、`小智`、`SenseVoice` 等。

## 指定 provider

脚本会自动选择当前最近线程使用的 provider。  
如果你明确知道目标 provider，也可以手动指定：

```powershell
.\scripts\recover-codex-sessions.ps1 -TargetProvider codexproxy_codex -Apply
```

## 脚本会做什么

执行 `-Apply` 后，脚本会：

1. 备份 `state_5.sqlite`
2. 备份所有将被修改的旧会话 `jsonl`
3. 把旧会话文件头里的 `model_provider` 从 `OpenAI` / `openai` 改成当前 provider
4. 同步更新 `state_5.sqlite` 的 `threads.model_provider`
5. 输出备份目录和修改数量

备份目录类似：

```text
C:\Users\<你>\.codex\restore-backups\provider-migration-20260605114559
```

## 回滚

如果恢复后不满意，可以用备份还原。

还原数据库：

```powershell
$root = "$env:USERPROFILE\.codex"
$backupRoot = "$root\restore-backups\provider-migration-YYYYMMDDHHMMSS"
Copy-Item -LiteralPath "$backupRoot\state_5.sqlite.bak" -Destination "$root\state_5.sqlite" -Force
```

还原会话文件：

```powershell
$backupRoot = "$env:USERPROFILE\.codex\restore-backups\provider-migration-YYYYMMDDHHMMSS"
$backupSessions = Join-Path $backupRoot 'sessions'
$sessionsRoot = "$env:USERPROFILE\.codex\sessions"

Get-ChildItem -Recurse -File -LiteralPath $backupSessions | ForEach-Object {
  $rel = $_.FullName.Substring($backupSessions.Length).TrimStart('\')
  $dest = Join-Path $sessionsRoot $rel
  Copy-Item -LiteralPath $_.FullName -Destination $dest -Force
}
```

## 注意

- 不要上传 `.codex` 目录，它可能包含私密聊天和密钥信息。
- 不要把 `auth.json` 发给别人。
- 不要直接删除 `state_5.sqlite`。
- 如果中文标题变乱码，通常是文件被非 UTF-8 方式重写了，请从备份恢复。

## 手动教程

更详细的手动排查和恢复说明见：

[docs/manual-recovery.md](docs/manual-recovery.md)

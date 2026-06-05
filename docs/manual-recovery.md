# 手动恢复教程

这份教程适合想先看清楚原因、再手动恢复的人。只想快速解决的话，优先看仓库根目录的 `README.md`。

## 原因

Codex 桌面端的本地会话通常保存在：

```text
C:\Users\<你>\.codex
```

切换登录方式、账号、模型供应商或本地代理后，新线程可能使用新的 `model_provider`，例如：

```text
codexproxy_codex
```

旧线程仍然是：

```text
OpenAI
openai
```

如果桌面端列表按当前 provider 过滤，旧记录就会看起来“消失”。实际聊天内容通常还在 `sessions` 目录里。

## 只读检查

打开 PowerShell：

```powershell
$root = "$env:USERPROFILE\.codex"
Get-ChildItem -Force -LiteralPath $root
```

查看旧会话文件：

```powershell
Get-ChildItem -Force -Recurse -File -LiteralPath "$root\sessions" -Filter "*.jsonl" |
  Sort-Object LastWriteTime -Descending |
  Select-Object -First 20 FullName, Length, LastWriteTime
```

查看数据库 provider 分布：

```powershell
sqlite3 "$root\state_5.sqlite" `
  "select model_provider, archived, count(*) from threads group by model_provider, archived order by model_provider, archived;"
```

如果看到旧 provider 和新 provider 混在一起，就可以继续。

## 备份

```powershell
$root = "$env:USERPROFILE\.codex"
$stamp = Get-Date -Format yyyyMMddHHmmss
$backupRoot = Join-Path $root "restore-backups\provider-migration-$stamp"
New-Item -ItemType Directory -Force -Path $backupRoot | Out-Null

sqlite3 "$root\state_5.sqlite" ".backup '$backupRoot\state_5.sqlite.bak'"
Write-Output "backupRoot=$backupRoot"
```

## 查看当前新 provider

```powershell
sqlite3 "$root\state_5.sqlite" `
  "select id,title,model_provider,cwd from threads order by updated_at desc limit 10;"
```

最新的新线程使用的 provider，一般就是要迁移到的目标 provider。

## 单条测试

先挑一条旧线程：

```powershell
sqlite3 "$root\state_5.sqlite" `
  "select id,rollout_path,model_provider,title from threads where model_provider in ('OpenAI','openai') order by updated_at desc limit 5;"
```

把其中一条的 `rollout_path` 复制出来，然后只改这一条：

```powershell
$session = "C:\Users\<你>\.codex\sessions\YYYY\MM\DD\rollout-xxx.jsonl"
$targetProvider = "codexproxy_codex"
$utf8 = New-Object System.Text.UTF8Encoding($false, $true)

Copy-Item -LiteralPath $session -Destination "$session.bak-provider-test"

$text = [System.IO.File]::ReadAllText($session, $utf8)
$replacement = '"model_provider":"' + $targetProvider + '"'
$text = $text.Replace('"model_provider":"OpenAI"', $replacement)
$text = $text.Replace('"model_provider":"openai"', $replacement)
[System.IO.File]::WriteAllText($session, $text, $utf8)

sqlite3 "$root\state_5.sqlite" `
  "update threads set model_provider='$targetProvider' where id='这里填线程ID';"
```

重启 Codex，搜索这条旧线程标题。能搜到再批量恢复。

## 批量恢复

推荐直接用脚本：

```powershell
.\scripts\recover-codex-sessions.ps1 -TargetProvider codexproxy_codex -Apply
```

## 回滚

把脚本输出的备份目录填回来：

```powershell
$root = "$env:USERPROFILE\.codex"
$backupRoot = "$root\restore-backups\provider-migration-YYYYMMDDHHMMSS"
Copy-Item -LiteralPath "$backupRoot\state_5.sqlite.bak" -Destination "$root\state_5.sqlite" -Force
```

如果脚本备份了会话文件，也可以还原：

```powershell
$backupSessions = Join-Path $backupRoot "sessions"
$sessionsRoot = "$root\sessions"

Get-ChildItem -Recurse -File -LiteralPath $backupSessions | ForEach-Object {
  $rel = $_.FullName.Substring($backupSessions.Length).TrimStart("\")
  $dest = Join-Path $sessionsRoot $rel
  Copy-Item -LiteralPath $_.FullName -Destination $dest -Force
}
```

## 不要做

- 不要删除 `.codex`
- 不要删除 `state_5.sqlite`
- 不要上传 `auth.json`
- 不要把 `.codex` 整个目录发给别人
- 不要用非 UTF-8 方式重写中文会话文件

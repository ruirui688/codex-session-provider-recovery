param(
  [string]$CodexHome = "$env:USERPROFILE\.codex",
  [string]$TargetProvider = "",
  [switch]$Apply
)

$ErrorActionPreference = "Stop"

function Fail($Message) {
  Write-Error $Message
  exit 1
}

function SqlScalar($Db, $Sql) {
  $value = & sqlite3 $Db $Sql
  if ($LASTEXITCODE -ne 0) {
    Fail "sqlite3 failed: $Sql"
  }
  return ($value | Select-Object -First 1)
}

$db = Join-Path $CodexHome "state_5.sqlite"
$sessionsRoot = Join-Path $CodexHome "sessions"

if (-not (Test-Path -LiteralPath $CodexHome)) {
  Fail "Codex home not found: $CodexHome"
}

if (-not (Test-Path -LiteralPath $db)) {
  Fail "state_5.sqlite not found: $db"
}

if (-not (Test-Path -LiteralPath $sessionsRoot)) {
  Fail "sessions folder not found: $sessionsRoot"
}

if (-not (Get-Command sqlite3 -ErrorAction SilentlyContinue)) {
  Fail "sqlite3 not found. Install SQLite or add sqlite3.exe to PATH."
}

if ([string]::IsNullOrWhiteSpace($TargetProvider)) {
  $TargetProvider = SqlScalar $db "select model_provider from threads where model_provider not in ('OpenAI','openai') order by updated_at desc limit 1;"
}

if ([string]::IsNullOrWhiteSpace($TargetProvider)) {
  Fail "Could not auto-detect target provider. Re-run with -TargetProvider <provider>."
}

$oldDbCount = SqlScalar $db "select count(*) from threads where model_provider in ('OpenAI','openai');"

$utf8 = New-Object System.Text.UTF8Encoding($false, $true)
$oldSessionFiles = New-Object System.Collections.Generic.List[string]
$scanErrors = New-Object System.Collections.Generic.List[string]

Get-ChildItem -Recurse -File -LiteralPath $sessionsRoot -Filter "*.jsonl" | ForEach-Object {
  $path = $_.FullName
  try {
    $fs = [System.IO.File]::Open(
      $path,
      [System.IO.FileMode]::Open,
      [System.IO.FileAccess]::Read,
      [System.IO.FileShare]::ReadWrite
    )

    try {
      $sr = New-Object System.IO.StreamReader($fs, $utf8, $true)
      $line = $sr.ReadLine()
      $sr.Close()
    } finally {
      $fs.Dispose()
    }

    if ($line -match '"model_provider":"OpenAI"|"model_provider":"openai"') {
      $oldSessionFiles.Add($path) | Out-Null
    }
  } catch {
    $scanErrors.Add("$path :: $($_.Exception.Message)") | Out-Null
  }
}

Write-Output "Codex home: $CodexHome"
Write-Output "Target provider: $TargetProvider"
Write-Output "Old-provider rows in database: $oldDbCount"
Write-Output "Old-provider session files: $($oldSessionFiles.Count)"

if ($scanErrors.Count -gt 0) {
  Write-Output ""
  Write-Output "Files skipped while scanning:"
  $scanErrors | Select-Object -First 20
}

if (-not $Apply) {
  Write-Output ""
  Write-Output "Dry run only. Nothing changed."
  Write-Output "Run again with -Apply to backup and migrate."
  exit 0
}

if (($oldDbCount -eq 0) -and ($oldSessionFiles.Count -eq 0)) {
  Write-Output "Nothing to migrate."
  exit 0
}

$stamp = Get-Date -Format yyyyMMddHHmmss
$backupRoot = Join-Path $CodexHome "restore-backups\provider-migration-$stamp"
New-Item -ItemType Directory -Force -Path $backupRoot | Out-Null

$dbBackup = Join-Path $backupRoot "state_5.sqlite.bak"
& sqlite3 $db ".backup '$dbBackup'"
if ($LASTEXITCODE -ne 0) {
  Fail "Database backup failed."
}

$replacementProvider = '"model_provider":"' + $TargetProvider + '"'
$changed = 0
$writeErrors = New-Object System.Collections.Generic.List[string]

foreach ($path in $oldSessionFiles) {
  try {
    $text = [System.IO.File]::ReadAllText($path, $utf8)
    $newText = $text.Replace('"model_provider":"OpenAI"', $replacementProvider)
    $newText = $newText.Replace('"model_provider":"openai"', $replacementProvider)

    if ($newText -ne $text) {
      $rel = $path.Substring($sessionsRoot.Length).TrimStart("\")
      $dest = Join-Path (Join-Path $backupRoot "sessions") $rel
      New-Item -ItemType Directory -Force -Path (Split-Path -Parent $dest) | Out-Null
      Copy-Item -LiteralPath $path -Destination $dest -Force
      [System.IO.File]::WriteAllText($path, $newText, $utf8)
      $changed++
    }
  } catch {
    $writeErrors.Add("$path :: $($_.Exception.Message)") | Out-Null
  }
}

& sqlite3 $db "update threads set model_provider='$TargetProvider' where model_provider in ('OpenAI','openai');"
if ($LASTEXITCODE -ne 0) {
  Fail "Database update failed. Backup is at: $backupRoot"
}

Write-Output ""
Write-Output "Migration complete."
Write-Output "Backup: $backupRoot"
Write-Output "Session files changed: $changed"

Write-Output ""
Write-Output "Provider summary:"
& sqlite3 $db "select model_provider,count(*) from threads group by model_provider order by model_provider;"

if ($writeErrors.Count -gt 0) {
  Write-Output ""
  Write-Output "Files failed while writing:"
  $writeErrors | Select-Object -First 20
}

Write-Output ""
Write-Output "Restart Codex Desktop, then search for old thread titles or project names."

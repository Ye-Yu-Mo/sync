#requires -Version 5
param(
  [switch]$RunFromConfig,
  [string]$ConfigPath,
  [string]$Task
)

$HostName = "23.94.111.42"
$Port = 22
$SshUser = "syncuser"
$SshPass = "nba0981057309"

$BaseDir   = Join-Path $env:LOCALAPPDATA "SftpSync"
$Config    = Join-Path $BaseDir "config.json"
$WinScpDir = Join-Path $BaseDir "winscp"
$WinScpCom = Join-Path $WinScpDir "WinSCP.com"
$WinScpUrl = "https://winscp.net/download/WinSCP-Portable.zip"
$script:LogFilePath = $null

function Write-LogLine {
  param(
    [string]$Message
  )
  if (-not $script:LogFilePath) { return }
  if ([string]::IsNullOrWhiteSpace($Message)) { return }
  $timestamp = (Get-Date -Format "yyyy-MM-dd HH:mm:ss")
  Add-Content -Path $script:LogFilePath -Value ("[{0}] {1}" -f $timestamp, $Message)
}

function Ensure-Dirs { if (!(Test-Path $BaseDir)) { New-Item -ItemType Directory -Path $BaseDir | Out-Null } if (!(Test-Path $WinScpDir)) { New-Item -ItemType Directory -Path $WinScpDir | Out-Null } }

function Start-TaskLogging {
  param(
    [string]$ConfigFile,
    [string]$TaskId
  )
  if (-not $ConfigFile -or -not $TaskId) { return }
  $configDir = Split-Path -Parent $ConfigFile
  if (-not $configDir) { $configDir = "." }
  $logDir = Join-Path $configDir "logs"
  if (!(Test-Path $logDir)) { New-Item -ItemType Directory -Path $logDir | Out-Null }
  $timestamp = Get-Date -Format "yyyyMMdd-HHmmss"
  $script:LogFilePath = Join-Path $logDir "$TaskId-$timestamp.log"
  New-Item -Path $script:LogFilePath -ItemType File -Force | Out-Null
}

function Install-WinSCP {
  if (Test-Path $WinScpCom) { return }
  Write-Host "[*] 未检测到 WinSCP，开始下载..."
  Ensure-Dirs
  $zip = Join-Path $WinScpDir "WinSCP-Portable.zip"
  try {
    Invoke-WebRequest -Uri $WinScpUrl -OutFile $zip
  } catch {
    Write-Error "下载 WinSCP 失败：$($_.Exception.Message)"
    exit 1
  }
  Add-Type -AssemblyName System.IO.Compression.FileSystem
  [System.IO.Compression.ZipFile]::ExtractToDirectory($zip, $WinScpDir)
  Remove-Item $zip -Force
  $global:WinScpCom = Get-ChildItem -Path $WinScpDir -Recurse -Filter WinSCP.com | Select-Object -First 1 -ExpandProperty FullName
  if (-not $global:WinScpCom) { Write-Error "未找到 WinSCP.com"; exit 1 }
}

function Read-Inputs {
  $fb = Read-Host "请选择 FileBrowser 用户名（yachen/xulei）"
  if ($fb -ne "yachen" -and $fb -ne "xulei") { Write-Error "只能输入 yachen 或 xulei"; exit 1 }
  $local = Read-Host "请输入需要同步的本地目录路径"
  if (-not (Test-Path $local)) { Write-Error "本地目录不存在：$local"; exit 1 }

  $sub = Read-Host "（可选）远程子目录（例如 ft 或 ft/project；留空=仅 /data/$fb）"
  if ($sub) {
    # 去首尾斜杠
    if ($sub.StartsWith("/")) { $sub = $sub.TrimStart("/") }
    if ($sub.EndsWith("/"))   { $sub = $sub.TrimEnd("/") }
    if ($sub -match "\.\.") { Write-Error "远程子目录不允许包含 '..'"; exit 1 }
  }

  $remote = "/data/$fb"
  if ($sub) { $remote = "$remote/$sub" }

  $obj = [pscustomobject]@{
    FbUser    = $fb
    LocalDir  = (Resolve-Path $local).Path
    RemoteDir = $remote
    Host      = $HostName
    Port      = $Port
    SshUser   = $SshUser
    SshPass   = $SshPass
  }
  Ensure-Dirs
  $obj | ConvertTo-Json | Set-Content -Path $Config -Encoding UTF8
  Write-Host "[*] 已保存配置到 $Config"
}

function Load-Config {
  if (-not (Test-Path $Config)) { Write-Error "找不到配置文件：$Config"; exit 1 }
  return Get-Content $Config -Raw | ConvertFrom-Json
}

function Normalize-RemoteBase {
  param([string]$Path)
  if (-not $Path) { return "/" }
  $tmp = $Path -replace "\\", "/"
  if (-not $tmp.StartsWith("/")) { $tmp = "/$tmp" }
  if ($tmp.Length -gt 1 -and $tmp.EndsWith("/")) { $tmp = $tmp.TrimEnd("/") }
  return $tmp
}

function Join-RemotePath {
  param(
    [string]$BaseDir,
    [string]$RelativeDir
  )
  if (-not $RelativeDir) { return $BaseDir }
  $rel = $RelativeDir -replace "\\", "/"
  if ($rel -eq "." -or $rel -eq "/") { return $BaseDir }
  $rel = $rel.Trim("/")
  if (-not $rel) { return $BaseDir }
  $trimBase = $BaseDir.TrimEnd("/")
  if (-not $trimBase) { $trimBase = "/" }
  if ($trimBase -eq "/") { return "/$rel" }
  return "$trimBase/$rel"
}

function Load-TaskFromJson {
  param(
    [Parameter(Mandatory)][string]$ConfigPath,
    [Parameter(Mandatory)][string]$TaskId
  )

  if (-not (Test-Path $ConfigPath)) {
    throw "找不到配置文件：$ConfigPath"
  }
  $json = Get-Content $ConfigPath -Raw | ConvertFrom-Json
  if (-not $json.server) { throw "配置缺少 server 节点" }
  if (-not $json.tasks) { throw "配置中 tasks 为空" }
  $task = $json.tasks | Where-Object { $_.id -eq $TaskId } | Select-Object -First 1
  if (-not $task) { throw "未找到任务 $TaskId" }

  $remoteBase = Normalize-RemoteBase -Path $json.server.remoteBaseDir
  $remoteDir = Join-RemotePath -BaseDir $remoteBase -RelativeDir $task.remoteDir

  $localDir = $task.localDir
  if (-not $localDir) { $localDir = $json.server.defaultLocalDir }
  if (-not $localDir) { throw "任务未指定本地目录" }
  $resolvedLocal = Resolve-Path -LiteralPath $localDir -ErrorAction Stop

  $obj = [pscustomobject]@{
    Host      = $json.server.host
    Port      = if ($json.server.port) { [int]$json.server.port } else { 22 }
    SshUser   = $json.server.username
    SshPass   = $json.server.password
    LocalDir  = $resolvedLocal.Path
    RemoteDir = $remoteDir
    TaskName  = $task.name
    TaskId    = $TaskId
    ConfigPath= (Resolve-Path -LiteralPath $ConfigPath).Path
  }

  foreach ($key in @("Host","SshUser","SshPass","RemoteDir")) {
    if (-not $obj.$key) { throw "配置缺少必要字段：$key" }
  }

  return $obj
}

function Sync-Once {
  param($cfg)
  $message = "[*] 开始同步：$($cfg.LocalDir) -> sftp://$($cfg.Host):$($cfg.Port)$($cfg.RemoteDir)"
  Write-Host $message
  Write-LogLine $message
  $scriptFile = Join-Path $BaseDir "winscp_sync.txt"
  @"
open sftp://$($cfg.SshUser):$($cfg.SshPass)@$($cfg.Host):$($cfg.Port) -hostkey=*
option batch abort
option confirm off
lcd "$($cfg.LocalDir)"
# 本地 -> 远程（上传），删远端多余文件，断点续传，并行 4
mirror -upload -delete -resume -parallel=4 . "$($cfg.RemoteDir)"
exit
"@ | Set-Content -Path $scriptFile -Encoding ASCII

  $output = & "$WinScpCom" "/ini=nul" "/script=$scriptFile" 2>&1
  if ($output) {
    $output | ForEach-Object {
      if ($_ -ne $null) {
        Write-Host $_
        Write-LogLine $_
      }
    }
  }
  if ($LASTEXITCODE -ne 0) {
    $err = "同步过程出现错误（WinSCP ExitCode=$LASTEXITCODE）"
    Write-LogLine $err
    Write-Error $err
    exit $LASTEXITCODE
  }
  Write-Host "[*] 同步完成。"
  Write-LogLine "[*] 同步完成。"
  if ($script:LogFilePath) {
    Write-Host "[*] 日志文件：$script:LogFilePath"
  }
}

function Setup-Schedule {
  $yn = Read-Host "是否设置为自动同步？(y/N)"
  if ($yn -notmatch '^[Yy]') { Write-Host "[*] 跳过自动同步设置。"; return }
  $min = Read-Host "请填写同步间隔（分钟，>=1）"
  if (-not ($min -as [int]) -or [int]$min -lt 1) { Write-Error "无效的分钟数"; exit 1 }

  $taskName = "SftpSync-FileBrowser"
  $action   = New-ScheduledTaskAction -Execute "powershell.exe" -Argument "-NoProfile -ExecutionPolicy Bypass -File `"$PSCommandPath`" -RunFromConfig"
  $trigger  = New-ScheduledTaskTrigger -Once -At (Get-Date).AddMinutes(1) -RepetitionInterval (New-TimeSpan -Minutes $min) -RepetitionDuration ([TimeSpan]::MaxValue)
  try {
    Register-ScheduledTask -TaskName $taskName -Action $action -Trigger $trigger -Description "SFTP Sync to FileBrowser every $min minutes" -Force | Out-Null
    Write-Host "[*] 已创建计划任务 '$taskName'（每 $min 分钟执行一次）。"
  } catch {
    Write-Error "创建计划任务失败：$($_.Exception.Message)"
    exit 1
  }
}

# ---- 主流程 ----
$mode = "Interactive"
if ($RunFromConfig) { $mode = "Env" }
if ($PSBoundParameters.ContainsKey("ConfigPath") -or $PSBoundParameters.ContainsKey("Task")) {
  if ($RunFromConfig) {
    Write-Error "-RunFromConfig 与 -ConfigPath/-Task 不能同时使用"
    exit 1
  }
  if (-not $ConfigPath -or -not $Task) {
    Write-Error "-ConfigPath 与 -Task 必须同时提供"
    exit 1
  }
  $mode = "Json"
}

switch ($mode) {
  "Env" {
    Install-WinSCP
    $cfg = Load-Config
    Sync-Once -cfg $cfg
    break
  }
  "Json" {
    Install-WinSCP
    try {
      $cfg = Load-TaskFromJson -ConfigPath $ConfigPath -TaskId $Task
    } catch {
      Write-Error $_.Exception.Message
      exit 1
    }
    Start-TaskLogging -ConfigFile $cfg.ConfigPath -TaskId $cfg.TaskId
    Sync-Once -cfg $cfg
    break
  }
  default {
    Install-WinSCP
    Read-Inputs
    $cfg = Load-Config
    Sync-Once -cfg $cfg
    Setup-Schedule
  }
}

#Requires -Version 5.1
<#
.SYNOPSIS
  윈도우: origin으로 push 후 맥북 자동 pull 알림

.USAGE
  .\push-and-notify-mac.ps1
  .\push-and-notify-mac.ps1 HEAD
#>
param(
    [string]$Ref = "HEAD"
)

$ErrorActionPreference = "Stop"
$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$RepoRoot = (Resolve-Path (Join-Path $ScriptDir "..\..")).Path

Set-Location $RepoRoot
git push origin $Ref
& (Join-Path $ScriptDir "notify-mac-sync.ps1")

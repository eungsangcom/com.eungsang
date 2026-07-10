#Requires -Version 5.1
<#
.SYNOPSIS
  윈도우에서 git push 직후 맥북에 POST /sync 호출

.USAGE
  .\notify-mac-sync.ps1
  git push; .\notify-mac-sync.ps1

.ENV
  MAC_GIT_SYNC_URL=http://100.118.66.51:8427/sync
#>
$ErrorActionPreference = "Continue"
$Url = if ($env:MAC_GIT_SYNC_URL) { $env:MAC_GIT_SYNC_URL } else { "http://100.118.66.51:8427/sync" }

Write-Host "==> POST $Url"
try {
    $resp = Invoke-WebRequest -Method POST -Uri $Url -ContentType "application/json" -TimeoutSec 120 -UseBasicParsing
    Write-Host $resp.Content
    Write-Host "HTTP $($resp.StatusCode)"
} catch {
    Write-Warning "mac sync notify failed (poll will still catch up within ~30s): $($_.Exception.Message)"
}

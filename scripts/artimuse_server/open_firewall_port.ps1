#Requires -Version 5.1
#Requires -RunAsAdministrator
<#
  Tailscale/LAN에서 맥미니 backend가 8426 포트로 접근할 수 있도록 방화벽 인바운드 규칙 추가.
  관리자 PowerShell에서 한 번만 실행.
#>
param(
    [int]$Port = 8426,
    [string]$RuleName = "Eungsang ArtiMuse Server"
)

$ErrorActionPreference = "Stop"

$existing = Get-NetFirewallRule -DisplayName $RuleName -ErrorAction SilentlyContinue
if ($existing) {
    Write-Host "Rule already exists: $RuleName"
    exit 0
}

New-NetFirewallRule `
    -DisplayName $RuleName `
    -Direction Inbound `
    -Action Allow `
    -Protocol TCP `
    -LocalPort $Port `
    -Profile Any | Out-Null

Write-Host "Firewall rule added: TCP $Port ($RuleName)"

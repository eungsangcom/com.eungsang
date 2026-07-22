#Requires -Version 5.1
#Requires -RunAsAdministrator
<#
  Tailscale/LAN에서 맥미니 backend가 8428 포트로 접근할 수 있도록 방화벽 인바운드 규칙 추가.
#>
param(
    [int]$Port = 8428,
    [string]$RuleName = "Eungsang NIMA Server"
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

#Requires -Version 5.1
<#
  관리자 PowerShell:
    .\open_firewall_port.ps1
#>
param([int]$Port = 8426)

$ErrorActionPreference = "Stop"
$RuleName = "Eungsang Windows Git Sync $Port"

$isAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole(
    [Security.Principal.WindowsBuiltInRole]::Administrator
)
if (-not $isAdmin) {
    throw "Run PowerShell as Administrator."
}

$existing = Get-NetFirewallRule -DisplayName $RuleName -ErrorAction SilentlyContinue
if ($existing) {
    Remove-NetFirewallRule -DisplayName $RuleName
}

New-NetFirewallRule `
    -DisplayName $RuleName `
    -Direction Inbound `
    -Action Allow `
    -Protocol TCP `
    -LocalPort $Port `
    -Profile Any | Out-Null

Write-Host "Allowed inbound TCP $Port ($RuleName)"

$ErrorActionPreference = "Continue"
Write-Host "==> NIMA rule details"
Get-NetFirewallRule -DisplayName "Eungsang NIMA Server" -ErrorAction SilentlyContinue | Format-List DisplayName,Enabled,Direction,Action,Profile
Get-NetFirewallRule -DisplayName "Eungsang NIMA Server" -ErrorAction SilentlyContinue | Get-NetFirewallPortFilter | Format-List *
Get-NetFirewallRule -DisplayName "Eungsang NIMA Server" -ErrorAction SilentlyContinue | Get-NetFirewallAddressFilter | Format-List *

Write-Host "==> ArtiMuse rule details"
Get-NetFirewallRule -DisplayName "ArtiMuse Server" -ErrorAction SilentlyContinue | Select-Object -First 1 | Get-NetFirewallPortFilter | Format-List *

Write-Host "==> recreate NIMA rule cleanly"
Get-NetFirewallRule -DisplayName "Eungsang NIMA Server" -ErrorAction SilentlyContinue | Remove-NetFirewallRule -ErrorAction SilentlyContinue
netsh advfirewall firewall delete rule name="Eungsang NIMA Server" | Out-Null
New-NetFirewallRule `
  -DisplayName "Eungsang NIMA Server" `
  -Direction Inbound `
  -Action Allow `
  -Protocol TCP `
  -LocalPort 8428 `
  -Profile Any `
  -RemoteAddress Any `
  -EdgeTraversalPolicy Allow | Out-Null

Get-NetFirewallRule -DisplayName "Eungsang NIMA Server" | Get-NetFirewallPortFilter | Format-List Protocol,LocalPort,RemotePort
Write-Host "done"

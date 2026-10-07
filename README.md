# PowerShell Helpdesk Toolkit

A set of PowerShell scripts that automate the repetitive tickets a tier-1 helpdesk tech handles every day: onboarding new hires, resetting passwords, inventorying machines, cleaning disks, and troubleshooting "I can't connect" calls.

## Scripts

| Script | What it does |
|---|---|
| `New-HDUser.ps1` | Bulk-creates AD users from a CSV (`FirstName,LastName,Department`), generates `firstinitial+lastname` usernames with dedup, places accounts in a target OU, adds users to matching department groups, forces password change at logon. Full `-WhatIf` support and run logging. |
| `Reset-HDPassword.ps1` | The "I can't log in" one-shot: resets the password (or generates a compliant 14-char one), unlocks locked-out accounts, forces change-at-next-logon, and writes an audit log entry. |
| `Get-SystemInventory.ps1` | Collects hostname, OS version/build, CPU, RAM, disk usage, IPs and MACs into a PSObject with optional CSV export — plus automatic low-disk / low-RAM warnings. |
| `Clear-TempFiles.ps1` | Safe disk cleanup (user temp, Windows temp, optional Windows Update cache, Recycle Bin). Skips in-use files and reports MB freed. |
| `Test-NetworkConnectivity.ps1` | Layered connectivity check: gateway ping → DNS resolution → external ping → TCP port tests (80/443, optional 3389). Color-coded pass/fail with a plain-English verdict on which layer failed first. |

## Skills demonstrated

- Active Directory administration via the `ActiveDirectory` module (`New-ADUser`, `Set-ADAccountPassword`, `Unlock-ADAccount`)
- CIM/WMI querying (`Get-CimInstance`) for hardware and OS inventory
- Advanced functions: comment-based help, `[CmdletBinding(SupportsShouldProcess)]`, parameter validation
- Error handling that degrades gracefully (locked files, missing OUs, duplicate usernames)
- Audit logging — every mutating script writes who did what and when

## What I learned

- How to write scripts another tech can actually run safely: `-WhatIf` everywhere, no hardcoded secrets, clear log output.
- AD onboarding end-to-end: username conventions, OU design, group membership, and why "change password at next logon" matters.
- Troubleshooting bottom-up through the network layers instead of guessing.

## How to run

```powershell
# Preview user creation without changing anything
.\scripts\New-HDUser.ps1 -CsvPath .\new-hires.csv -TargetOU "OU=Users,DC=lab,DC=local" -DefaultPassword "Temp#2026!" -WhatIf

# Password reset with generated password
.\scripts\Reset-HDPassword.ps1 -Identity jdoe

# Inventory this machine, append to a shared CSV
.\scripts\Get-SystemInventory.ps1 -ExportCsv \\fileserver\it\inventory.csv

# Disk cleanup (preview first)
.\scripts\Clear-TempFiles.ps1 -WhatIf

# "Can't reach the file server" workflow
.\scripts\Test-NetworkConnectivity.ps1 -TargetHost "fileserver01" -IncludeRdp
```

> **Note:** AD scripts require the RSAT ActiveDirectory module (`Add-WindowsFeature RSAT-AD-PowerShell`) and an account with rights to manage users in the target OU. Run cleanup/inventory scripts elevated for full results.

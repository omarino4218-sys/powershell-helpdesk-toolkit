# Validation Log

How each script in this toolkit was actually tested. Copy the template for
every new entry. Be honest: a script that was only syntax-reviewed is not
"tested on Windows".

## Template

```
Date:
Environment: (OS build, PowerShell version, domain-joined? RSAT installed?)
Command / procedure:
Expected result:
Observed result:
Evidence: (sanitized log excerpt, screenshot description — no real usernames,
           passwords, or internal hostnames)
```

## Entries

### 2026-10-08 — Syntax review of all five scripts (no Windows execution)

- **Environment:** Linux dev machine (no Windows available). PowerShell was
  not installed; the ActiveDirectory module cmdlets (`New-ADUser`,
  `Set-ADAccountPassword`, etc.) cannot run outside Windows.
- **Command / procedure:** Manual read-through of `New-HDUser.ps1`,
  `Reset-HDPassword.ps1`, `Get-SystemInventory.ps1`, `Clear-TempFiles.ps1`,
  and `Test-NetworkConnectivity.ps1` — checked parameter handling,
  `-WhatIf`/`-ErrorAction` usage, logging paths, and that examples match
  actual script parameters and file locations.
- **Expected result:** N/A (review, not execution).
- **Observed result:** Review only. The AD-dependent scripts
  (`New-HDUser.ps1`, `Reset-HDPassword.ps1`) have NOT been executed against
  a real domain. `Get-SystemInventory.ps1`, `Clear-TempFiles.ps1`, and
  `Test-NetworkConnectivity.ps1` have NOT been run on Windows either.
- **Evidence:** Code review notes only — no execution logs exist yet.
- **Next step:** Run the non-AD scripts on a Windows 10/11 machine and the
  AD scripts in an isolated lab domain, then record results here using the
  template above.

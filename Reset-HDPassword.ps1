<#
.SYNOPSIS
    Resets an Active Directory user's password and unlocks the account.

.DESCRIPTION
    The classic tier-1 ticket: "I can't log in." This script handles the full
    workflow in one shot — resets the password (or generates a compliant one),
    unlocks a locked-out account, forces a password change at next logon, and
    writes every action to a log file for the ticket record.

.PARAMETER Identity
    SamAccountName, UPN, or distinguished name of the user.

.PARAMETER NewPassword
    The new temporary password. If omitted, a random 14-character password
    meeting default AD complexity is generated.

.PARAMETER LogPath
    Path to the audit log. Defaults to .\Reset-HDPassword.log.

.EXAMPLE
    .\Reset-HDPassword.ps1 -Identity jdoe
    Generates a random password, resets, unlocks, forces change at logon.

.EXAMPLE
    .\Reset-HDPassword.ps1 -Identity jdoe -NewPassword "Temp#4821!" -WhatIf
    Preview mode — shows what would happen.

.NOTES
    Requires the ActiveDirectory module and password-reset rights on the account.
    Never email or chat the temporary password in cleartext — read it to the
    user over the phone or via your org's secure channel.
#>
[CmdletBinding(SupportsShouldProcess = $true)]
param(
    [Parameter(Mandatory = $true)]
    [string]$Identity,

    [string]$NewPassword,

    [string]$LogPath = (Join-Path $PSScriptRoot "Reset-HDPassword.log")
)

if (-not (Get-Module -ListAvailable -Name ActiveDirectory)) {
    Write-Error "The ActiveDirectory module is not installed. Run: Add-WindowsFeature RSAT-AD-PowerShell"
    exit 1
}
Import-Module ActiveDirectory -ErrorAction Stop

function Write-HDLog {
    param([string]$Message)
    $stamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    "[$stamp] $Message" | Out-File -FilePath $LogPath -Append -Encoding utf8
}

function New-CompliantPassword {
    # 14 chars: upper, lower, digit, symbol — satisfies default AD complexity
    $upper   = 'ABCDEFGHJKLMNPQRSTUVWXYZ'
    $lower   = 'abcdefghijkmnopqrstuvwxyz'
    $digits  = '23456789'
    $symbols = '!@#$%^&*'
    $all = $upper + $lower + $digits + $symbols
    $rng = [System.Random]::new()
    $chars = @(
        $upper[$rng.Next($upper.Length)],
        $lower[$rng.Next($lower.Length)],
        $digits[$rng.Next($digits.Length)],
        $symbols[$rng.Next($symbols.Length)]
    )
    1..10 | ForEach-Object { $chars += $all[$rng.Next($all.Length)] }
    -join ($chars | Sort-Object { $rng.Next() })
}

try {
    $user = Get-ADUser -Identity $Identity -Properties LockedOut, PasswordLastSet -ErrorAction Stop
}
catch {
    Write-Error "User not found: $Identity"
    exit 1
}

if (-not $NewPassword) { $NewPassword = New-CompliantPassword }
$secure = ConvertTo-SecureString $NewPassword -AsPlainText -Force
$admin = "$env:USERDOMAIN\$env:USERNAME"

if ($PSCmdlet.ShouldProcess($user.SamAccountName, "Reset password + unlock account")) {
    Set-ADAccountPassword -Identity $user -Reset -NewPassword $secure -ErrorAction Stop
    Write-HDLog "PASSWORD RESET for $($user.SamAccountName) by $admin"

    if ($user.LockedOut) {
        Unlock-ADAccount -Identity $user -ErrorAction Stop
        Write-HDLog "UNLOCKED $($user.SamAccountName) (was locked out)"
        Write-Host "Account was locked out — unlocked." -ForegroundColor Yellow
    }

    Set-ADUser -Identity $user -ChangePasswordAtLogon $true -ErrorAction Stop
    Write-HDLog "FORCE-CHANGE-AT-LOGON set for $($user.SamAccountName)"

    Write-Host "`nDone for $($user.DisplayName) ($($user.SamAccountName)):" -ForegroundColor Green
    Write-Host "  - Password reset, account unlocked, must change at next logon"
    Write-Host "  - Temporary password: $NewPassword" -ForegroundColor Cyan
    Write-Host "  - Logged to: $LogPath"
    Write-Warning "Share the temporary password securely — never paste it into a ticket or chat."
}

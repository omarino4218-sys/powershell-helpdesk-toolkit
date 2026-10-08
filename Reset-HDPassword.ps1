<#
.SYNOPSIS
    Resets an Active Directory user's password and unlocks the account.

.DESCRIPTION
    The classic tier-1 ticket: "I can't log in." This script handles the full
    workflow in one shot — resets the password (or generates a random 14-char
    one meeting default AD complexity), unlocks a locked-out account, forces
    a password change at next logon, and writes every action to a log file
    for the ticket record.

.PARAMETER Identity
    SamAccountName, UPN, or distinguished name of the user.

.PARAMETER NewPassword
    The new temporary password. If omitted, a random 14-character password
    meeting default AD complexity is generated with a cryptographically
    secure RNG. Always deliver it over a verified channel, never in a ticket.

.PARAMETER LogPath
    Path to the audit log. Defaults to .\Reset-HDPassword.log.

.EXAMPLE
    .\Reset-HDPassword.ps1 -Identity jdoe
    Generates a random password, resets, unlocks, forces change at logon.

.EXAMPLE
    $tempPw = Read-Host "Temporary password" -AsSecureString
    .\Reset-HDPassword.ps1 -Identity jdoe `
        -NewPassword ([System.Net.NetworkCredential]::new("", $tempPw).Password) -WhatIf
    Preview mode — shows what would happen. Prompts securely instead of
    putting a password in cleartext on the command line.

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
    # 14 chars drawn from upper/lower/digit/symbol — satisfies the DEFAULT AD
    # complexity policy (3 of 4 character classes). "Compliant" here means
    # default-policy compliant only: your domain may enforce a longer minimum
    # length, password history, or fine-grained policies, so verify against
    # your actual password policy before relying on this.
    # Uses a cryptographically secure RNG (System.Security.Cryptography.
    # RandomNumberGenerator), not System.Random.
    $upper   = 'ABCDEFGHJKLMNPQRSTUVWXYZ'
    $lower   = 'abcdefghijkmnopqrstuvwxyz'
    $digits  = '23456789'
    $symbols = '!@#$%^&*'
    $all = $upper + $lower + $digits + $symbols
    $rng = [System.Security.Cryptography.RandomNumberGenerator]::Create()
    try {
        $pick = {
            param([string]$pool)
            $b = New-Object byte[] 4
            $rng.GetBytes($b)
            $pool[[BitConverter]::ToUInt32($b, 0) % $pool.Length]
        }
        $chars = @(
            (& $pick $upper),
            (& $pick $lower),
            (& $pick $digits),
            (& $pick $symbols)
        )
        1..10 | ForEach-Object { $chars += (& $pick $all) }
        # Fisher-Yates shuffle with the same secure RNG
        for ($i = $chars.Count - 1; $i -gt 0; $i--) {
            $b = New-Object byte[] 4
            $rng.GetBytes($b)
            $j = [BitConverter]::ToUInt32($b, 0) % ($i + 1)
            $tmp = $chars[$i]; $chars[$i] = $chars[$j]; $chars[$j] = $tmp
        }
        -join $chars
    }
    finally {
        $rng.Dispose()
    }
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

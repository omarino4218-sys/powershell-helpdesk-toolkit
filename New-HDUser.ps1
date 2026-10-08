<#
.SYNOPSIS
    Bulk-creates Active Directory user accounts from a CSV file.

.DESCRIPTION
    Reads a CSV of new hires and creates one enabled AD user account per row.
    Usernames are generated as first-initial + last name (e.g. jdoe), accounts
    are placed in the OU you specify, and each user is added to a security
    group matching their department when one exists. Every action is written
    to a log file so onboarding work is auditable.

    Typical helpdesk use: HR sends the new-hire spreadsheet on Monday morning,
    you run one command, and 20 accounts are ready before standup.

.PARAMETER CsvPath
    Path to the CSV file. Required columns: FirstName, LastName, Department.
    Example row:  Omar,Martinez,IT

.PARAMETER TargetOU
    Distinguished name of the OU where accounts are created.
    Example: "OU=Users,OU=Corp,DC=lab,DC=local"

.PARAMETER DefaultPassword
    Temporary password assigned to every new account. Users are forced to
    change it at first logon.

.PARAMETER LogPath
    Path to the run log. Defaults to .\New-HDUser.log in the script folder.

.EXAMPLE
    .\New-HDUser.ps1 -CsvPath .\examples\new-hires.csv -TargetOU "OU=Users,DC=lab,DC=local" -DefaultPassword "Temp#2026!" -WhatIf
    Shows what WOULD be created without creating anything.

.EXAMPLE
    .\New-HDUser.ps1 -CsvPath .\examples\new-hires.csv -TargetOU "OU=Users,DC=lab,DC=local" -DefaultPassword "Temp#2026!"
    Creates the accounts for real.

.NOTES
    Requires the ActiveDirectory PowerShell module and an account with rights
    to create users in the target OU (e.g. Account Operators or Domain Admins).
#>
[CmdletBinding(SupportsShouldProcess = $true)]
param(
    [Parameter(Mandatory = $true)]
    [ValidateScript({ Test-Path $_ -PathType Leaf })]
    [string]$CsvPath,

    [Parameter(Mandatory = $true)]
    [string]$TargetOU,

    [Parameter(Mandatory = $true)]
    [string]$DefaultPassword,

    [string]$LogPath = (Join-Path $PSScriptRoot "New-HDUser.log")
)

# --- Pre-flight checks -------------------------------------------------------
if (-not (Get-Module -ListAvailable -Name ActiveDirectory)) {
    Write-Error "The ActiveDirectory module is not installed. Run: Add-WindowsFeature RSAT-AD-PowerShell"
    exit 1
}
Import-Module ActiveDirectory -ErrorAction Stop

try {
    $null = Get-ADOrganizationalUnit -Identity $TargetOU -ErrorAction Stop
}
catch {
    Write-Error "Target OU not found: $TargetOU"
    exit 1
}

function Write-HDLog {
    param([string]$Message)
    $stamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    "[$stamp] $Message" | Out-File -FilePath $LogPath -Append -Encoding utf8
}

$securePass = ConvertTo-SecureString $DefaultPassword -AsPlainText -Force
$created = 0
$skipped = 0

# --- Main loop ---------------------------------------------------------------
Import-Csv -Path $CsvPath | ForEach-Object {
    $first = $_.FirstName.Trim()
    $last  = $_.LastName.Trim()
    $dept  = $_.Department.Trim()

    if (-not $first -or -not $last) {
        Write-Warning "Skipping row with missing name: $($_.FirstName) $($_.LastName)"
        Write-HDLog "SKIP: incomplete row (dept=$dept)"
        $skipped++
        return
    }

    # Username: first initial + last name, lowercase, no spaces (jdoe)
    $baseName = (($first[0] + $last) -replace '[^a-zA-Z0-9]', '').ToLower()
    $sam = $baseName
    $n = 1
    while (Get-ADUser -Filter "SamAccountName -eq '$sam'" -ErrorAction SilentlyContinue) {
        $n++
        $sam = "$baseName$n"   # jdoe -> jdoe2 -> jdoe3 ...
    }

    $upn = "$sam@$((Get-ADDomain).DNSRoot)"
    $display = "$first $last"

    $newUserParams = @{
        Name                  = $display
        GivenName             = $first
        Surname               = $last
        SamAccountName        = $sam
        UserPrincipalName     = $upn
        DisplayName           = $display
        Description           = "Dept: $dept"
        Department            = $dept
        Path                  = $TargetOU
        AccountPassword       = $securePass
        Enabled               = $true
        ChangePasswordAtLogon = $true
    }

    if ($PSCmdlet.ShouldProcess($display, "Create AD user '$sam' in $TargetOU")) {
        try {
            New-ADUser @newUserParams -ErrorAction Stop
            Write-HDLog "CREATED: $display ($sam) in $TargetOU"
            Write-Host "Created: $display ($sam)" -ForegroundColor Green
            $created++

            # Add to a department group if one exists (e.g. "IT", "HR")
            $group = Get-ADGroup -Filter "Name -eq '$dept'" -ErrorAction SilentlyContinue
            if ($group) {
                Add-ADGroupMember -Identity $group -Members $sam -ErrorAction SilentlyContinue
                Write-HDLog "GROUP: added $sam to $($group.Name)"
            }
        }
        catch {
            Write-Warning "Failed to create $display : $($_.Exception.Message)"
            Write-HDLog "FAILED: $display - $($_.Exception.Message)"
            $skipped++
        }
    }
}

Write-HDLog "Run complete: $created created, $skipped skipped"
Write-Host "`nDone. Created: $created | Skipped: $skipped | Log: $LogPath" -ForegroundColor Cyan

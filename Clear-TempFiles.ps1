<#
.SYNOPSIS
    Safely cleans temp files and caches, reporting how much space was freed.

.DESCRIPTION
    Empties the current user's temp folder, the Windows temp folder, and
    (optionally) the Windows Update download cache, then reports space
    reclaimed. Skips files that are in use instead of failing. This is the
    scripted version of the first thing you try when a user reports a
    "slow computer" or a disk-full alert fires.

.PARAMETER IncludeWindowsUpdateCache
    Also clears C:\Windows\SoftwareDistribution\Download (staged update files).
    Windows Update re-downloads what it needs.

.PARAMETER IncludeRecycleBin
    Also empties the Recycle Bin. Off by default — emptying the bin is
    destructive and its reclaimed space is reported separately, not as part of
    the temp-folder total.

.PARAMETER LogPath
    Path to the cleanup log. Defaults to .\Clear-TempFiles.log.

.EXAMPLE
    .\Clear-TempFiles.ps1 -WhatIf
    Preview what would be deleted.

.EXAMPLE
    .\Clear-TempFiles.ps1 -IncludeWindowsUpdateCache -IncludeRecycleBin
    Full cleanup including staged Windows Update files and the Recycle Bin.

.NOTES
    Run elevated for best results (some system temp files need admin rights).
    Never deletes anything outside the known-safe temp locations below.
#>
[CmdletBinding(SupportsShouldProcess = $true)]
param(
    [switch]$IncludeWindowsUpdateCache,

    [switch]$IncludeRecycleBin,

    [string]$LogPath = (Join-Path $PSScriptRoot "Clear-TempFiles.log")
)

function Write-HDLog {
    param([string]$Message)
    $stamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    "[$stamp] $Message" | Out-File -FilePath $LogPath -Append -Encoding utf8
}

function Get-FolderSizeMB {
    param([string]$Path)
    if (-not (Test-Path $Path)) { return 0 }
    $bytes = (Get-ChildItem $Path -Recurse -Force -File -ErrorAction SilentlyContinue |
        Measure-Object -Property Length -Sum).Sum
    [math]::Round($bytes / 1MB, 2)
}

$targets = @(
    $env:TEMP,                                  # current user temp
    (Join-Path $env:SystemRoot "Temp"),         # system temp
    (Join-Path $env:LOCALAPPDATA "Temp")        # local appdata temp (same as $env:TEMP usually)
) | Select-Object -Unique

if ($IncludeWindowsUpdateCache) {
    $targets += Join-Path $env:SystemRoot "SoftwareDistribution\Download"
}

$totalFreedMB = 0
Write-HDLog "Cleanup started by $env:USERNAME on $env:COMPUTERNAME"

foreach ($folder in $targets) {
    if (-not (Test-Path $folder)) { continue }

    $beforeMB = Get-FolderSizeMB $folder
    $deleted = 0
    $failed  = 0

    Get-ChildItem $folder -Recurse -Force -ErrorAction SilentlyContinue | ForEach-Object {
        if ($PSCmdlet.ShouldProcess($_.FullName, "Delete")) {
            try {
                Remove-Item $_.FullName -Recurse -Force -ErrorAction Stop
                $deleted++
            }
            catch {
                $failed++   # file in use — skip quietly, don't fail the run
            }
        }
    }

    $afterMB = Get-FolderSizeMB $folder
    $freedMB = [math]::Round($beforeMB - $afterMB, 2)
    $totalFreedMB += $freedMB

    $msg = "$folder : deleted $deleted items ($failed locked/skipped), freed ${freedMB} MB"
    Write-Host $msg
    Write-HDLog $msg
}

# Recycle Bin is opt-in only: emptying it is destructive, and its reclaimed
# space is NOT part of the temp-folder total reported below.
if ($IncludeRecycleBin) {
    if ($PSCmdlet.ShouldProcess("Recycle Bin", "Empty")) {
        try {
            Clear-RecycleBin -Force -ErrorAction Stop
            Write-HDLog "Recycle Bin emptied (opt-in)"
            Write-Host "Recycle Bin emptied."
        }
        catch {
            Write-HDLog "Recycle Bin: skipped ($($_.Exception.Message))"
        }
    }
}

Write-HDLog "Cleanup complete. Temp-folder space reclaimed: $totalFreedMB MB"
Write-Host "`nTemp-folder space reclaimed: $totalFreedMB MB" -ForegroundColor Green
Write-Host "Log: $LogPath" -ForegroundColor Cyan

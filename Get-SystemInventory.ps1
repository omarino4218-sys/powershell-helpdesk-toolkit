<#
.SYNOPSIS
    Collects a hardware/software inventory snapshot of a Windows machine.

.DESCRIPTION
    Queries WMI/CIM for hostname, OS version, CPU, RAM, disk usage, and
    network adapters (IP/MAC), then outputs a single PSObject. Supports CSV
    export so you can inventory a whole floor of machines and hand the
    spreadsheet to asset management.

    Typical helpdesk use: ticket says "computer is slow" — run this first and
    you instantly know if the disk is 98% full or the box has 4 GB of RAM.

.PARAMETER ExportCsv
    Path to a CSV file the inventory row is appended to.

.EXAMPLE
    .\Get-SystemInventory.ps1
    Outputs the inventory object to the pipeline (pipe to Format-List for a
    readable view).

.EXAMPLE
    .\Get-SystemInventory.ps1 -ExportCsv .\inventory.csv
    Appends the inventory row to inventory.csv (creates it with headers if new).

.NOTES
    Run locally on the target machine, or wrap in Invoke-Command for remote
    collection (requires PSRemoting / WinRM).
#>
[CmdletBinding()]
param(
    [string]$ExportCsv
)

$os   = Get-CimInstance Win32_OperatingSystem
$cpu  = Get-CimInstance Win32_Processor | Select-Object -First 1
$mem  = Get-CimInstance Win32_ComputerSystem
$disk = Get-CimInstance Win32_LogicalDisk -Filter "DriveType = 3"   # local fixed disks
$net  = Get-CimInstance Win32_NetworkAdapterConfiguration -Filter "IPEnabled = True"

$diskSummary = $disk | ForEach-Object {
    $pctFree = if ($_.Size -gt 0) { [math]::Round(($_.FreeSpace / $_.Size) * 100, 1) } else { 0 }
    "$($_.DeviceID) $([math]::Round($_.Size / 1GB, 1))GB ($pctFree% free)"
}

$inventory = [PSCustomObject]@{
    Hostname      = $env:COMPUTERNAME
    OS            = $os.Caption
    OSVersion     = $os.Version
    OSBuild       = $os.BuildNumber
    LastBoot      = $os.LastBootUpTime
    CPU           = $cpu.Name.Trim()
    CPUCores      = $cpu.NumberOfCores
    RAM_GB        = [math]::Round($mem.TotalPhysicalMemory / 1GB, 1)
    Disks         = ($diskSummary -join ' | ')
    IPAddresses   = (($net.IPAddress | Where-Object { $_ -match '\.' }) -join ', ')
    MACAddresses  = ($net.MACAddress -join ', ')
    CollectedAt   = (Get-Date -Format "yyyy-MM-dd HH:mm:ss")
    CollectedBy   = "$env:USERDOMAIN\$env:USERNAME"
}

# Health flags always run, even without -ExportCsv — the tech needs these
# on screen for a one-off check, not just in the exported report.
foreach ($d in $disk) {
    $pctFree = if ($d.Size -gt 0) { ($d.FreeSpace / $d.Size) * 100 } else { 100 }
    if ($pctFree -lt 10) {
        Write-Warning "LOW DISK: $($d.DeviceID) has only $([math]::Round($pctFree,1))% free — likely cause of slowness."
    }
}
if (($mem.TotalPhysicalMemory / 1GB) -lt 8) {
    Write-Warning "LOW RAM: $([math]::Round($mem.TotalPhysicalMemory / 1GB, 1)) GB installed."
}

if ($ExportCsv) {
    $exists = Test-Path $ExportCsv
    $inventory | Select-Object Hostname, OS, OSVersion, OSBuild, LastBoot, CPU,
        CPUCores, RAM_GB, Disks, IPAddresses, MACAddresses, CollectedAt, CollectedBy |
        Export-Csv -Path $ExportCsv -Append -NoTypeInformation -Encoding utf8
    if (-not $exists) {
        Write-Host "Created $ExportCsv" -ForegroundColor Green
    }
    else {
        Write-Host "Appended to $ExportCsv" -ForegroundColor Green
    }
}

# Return the raw object — callers choose their own formatting
# (e.g. .\Get-SystemInventory.ps1 | Format-List).
$inventory

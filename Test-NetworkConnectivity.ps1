<#
.SYNOPSIS
    Runs a layered network connectivity check and reports pass/fail per layer.

.DESCRIPTION
    Troubleshoots "I can't get to X" the way the OSI model says you should —
    bottom up:
      1. Local stack: can we ping the default gateway?
      2. DNS: can we resolve names (and is the DNS server itself reachable)?
      3. Internet: can we ping an external IP (bypasses DNS)?
      4. TCP: are the ports the app needs actually open (80/443 web, 3389 RDP)?

    Output is a color-coded table plus a plain-English verdict per layer, so
    even a brand-new tech can tell whether it's a local, DNS, or app problem.

.PARAMETER TargetHost
    Hostname to resolve and probe with TCP (default: www.google.com).

.PARAMETER TcpPorts
    TCP ports to test against TargetHost (default: 80, 443).

.PARAMETER IncludeRdp
    Also test TCP 3389 against TargetHost (handy for "can't RDP" tickets).

.EXAMPLE
    .\Test-NetworkConnectivity.ps1
    Full check against the defaults.

.EXAMPLE
    .\Test-NetworkConnectivity.ps1 -TargetHost "fileserver01" -IncludeRdp
    "Can't reach the file server / can't RDP" ticket workflow.

.NOTES
    Ping can be blocked by host firewalls — a failed ping with passing TCP
    usually means ICMP is filtered, not that the host is down.
#>
[CmdletBinding()]
param(
    [string]$TargetHost = "www.google.com",

    [int[]]$TcpPorts = @(80, 443),

    [switch]$IncludeRdp
)

if ($IncludeRdp) { $TcpPorts += 3389 }

$results = [System.Collections.Generic.List[object]]::new()

function Add-Check {
    param([string]$Layer, [string]$Test, [bool]$Passed, [string]$Detail)
    $results.Add([PSCustomObject]@{
        Layer  = $Layer
        Test   = $Test
        Result = if ($Passed) { "PASS" } else { "FAIL" }
        Detail = $Detail
    })
}

# --- Layer 1: default gateway -------------------------------------------------
$gateway = (Get-NetRoute -DestinationPrefix "0.0.0.0/0" -ErrorAction SilentlyContinue |
    Sort-Object RouteMetric | Select-Object -First 1).NextHop
if ($gateway) {
    $pingGw = Test-Connection -ComputerName $gateway -Count 2 -Quiet -ErrorAction SilentlyContinue
    Add-Check "Local" "Ping gateway $gateway" $pingGw "Gateway $(if ($pingGw) { 'reachable — local NIC/cable/switch OK' } else { 'UNREACHABLE — check cable, Wi-Fi, or switch port' })"
}
else {
    Add-Check "Local" "Find gateway" $false "No default route — DHCP may have failed (run ipconfig /renew)"
}

# --- Layer 2: DNS --------------------------------------------------------------
$dnsServers = (Get-DnsClientServerAddress -AddressFamily IPv4 -ErrorAction SilentlyContinue |
    Where-Object { $_.ServerAddresses }).ServerAddresses | Select-Object -Unique
foreach ($dns in $dnsServers) {
    $pingDns = Test-Connection -ComputerName $dns -Count 2 -Quiet -ErrorAction SilentlyContinue
    Add-Check "DNS" "Ping DNS $dns" $pingDns "$(if ($pingDns) { 'DNS server reachable' } else { 'DNS server not pingable' })"
}
try {
    $resolved = Resolve-DnsName -Name $TargetHost -ErrorAction Stop |
        Where-Object { $_.IPAddress } | Select-Object -First 1
    Add-Check "DNS" "Resolve $TargetHost" $true "Resolved to $($resolved.IPAddress)"
    $targetIp = $resolved.IPAddress
}
catch {
    Add-Check "DNS" "Resolve $TargetHost" $false "Name resolution FAILED — $($_.Exception.Message)"
    $targetIp = $null
}

# --- Layer 3: internet (ping external IP, bypasses DNS) -------------------------
# A failed ping here is INCONCLUSIVE, not proof of "no internet" — ICMP is
# commonly filtered by firewalls even when the path works. Trust the TCP
# results below over this ping.
$pingExt = Test-Connection -ComputerName "8.8.8.8" -Count 2 -Quiet -ErrorAction SilentlyContinue
Add-Check "Internet" "Ping 8.8.8.8" $pingExt "$(if ($pingExt) { 'Internet path OK' } else { 'External ICMP test failed; connectivity is inconclusive — check TCP results' })"

# --- Layer 4: TCP ports ----------------------------------------------------------
if ($targetIp) {
    foreach ($port in ($TcpPorts | Sort-Object -Unique)) {
        $tcp = Test-NetConnection -ComputerName $targetIp -Port $port -WarningAction SilentlyContinue
        Add-Check "TCP" "Port $port on $TargetHost" $tcp.TcpTestSucceeded `
            "$(if ($tcp.TcpTestSucceeded) { "Port open (${port})" } else { "Port closed/filtered — app or host firewall" })"
    }
}
else {
    # Not a failure — the checks were skipped for lack of a target IP.
    $results.Add([PSCustomObject]@{
        Layer  = "TCP"
        Test   = "Port tests"
        Result = "SKIPPED"
        Detail = "Skipped — DNS resolution failed, no target IP to test"
    })
}

# --- Report ----------------------------------------------------------------------
$results | Format-Table -AutoSize | Out-String | Write-Host
foreach ($r in $results) {
    $color = if ($r.Result -eq "PASS") { "Green" } elseif ($r.Result -eq "SKIPPED") { "Gray" } else { "Red" }
    Write-Host ("[{0}] {1}: {2}" -f $r.Result, $r.Test, $r.Detail) -ForegroundColor $color
}

$fails = ($results | Where-Object { $_.Result -eq "FAIL" }).Count
Write-Host ""
if ($fails -eq 0) {
    Write-Host "ALL CHECKS PASSED — network path to $TargetHost is healthy. If the app still fails, suspect the app itself or credentials." -ForegroundColor Green
}
else {
    $firstFail = ($results | Where-Object { $_.Result -eq "FAIL" } | Select-Object -First 1).Layer
    Write-Host "First failure at layer: $firstFail — start troubleshooting there (fix lower layers before upper ones)." -ForegroundColor Yellow
}

# dirused M10b3 jump-box probes: P1, P2, P3, P8 (a, b, d), P10, P12.
# Creates tasks only under \dirused-probe\<SID>\ and files only under %LOCALAPPDATA%\dirused-probe\.
# P3 runs dir and icacls (read-only) on the server share. Nothing is deleted on the server.
#
#   powershell -ExecutionPolicy Bypass -File dirused-m10b3-probes.ps1 setup [-P3Time 23:30]
#   powershell -ExecutionPolicy Bypass -File dirused-m10b3-probes.ps1 run12
#   powershell -ExecutionPolicy Bypass -File dirused-m10b3-probes.ps1 collect
#   powershell -ExecutionPolicy Bypass -File dirused-m10b3-probes.ps1 cleanup
param(
    [Parameter(Mandatory = $true, Position = 0)][ValidateSet('setup', 'run12', 'collect', 'cleanup')][string]$Mode,
    [string]$P3Time = '23:30',
    [int]$P2bMinutes = 40,
    [string]$Share = '\\us03p02ffm01\d$\Tomcat\Tomcat\logs'
)
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$sid = [Security.Principal.WindowsIdentity]::GetCurrent().User.Value
$folder = "\dirused-probe\$sid\"
$root = Join-Path $env:LOCALAPPDATA 'dirused-probe'
$state = Join-Path $root 'state.txt'

function Boundary([datetime]$t) { $t.ToString("yyyy-MM-dd'T'HH:mm:00zzz", [Globalization.CultureInfo]::InvariantCulture) }

function TaskXml([string]$name, [datetime]$run, [string]$command) {
    $start = Boundary $run
    $end = Boundary $run.AddDays(1)
    $cmd = [Security.SecurityElement]::Escape($command)
    @"
<?xml version="1.0" encoding="UTF-16"?>
<Task version="1.2" xmlns="http://schemas.microsoft.com/windows/2004/02/mit/task">
  <RegistrationInfo>
    <Description>dirused probe $name</Description>
    <SecurityDescriptor>D:P(A;;FA;;;$sid)(A;;FA;;;SY)(A;;FA;;;BA)</SecurityDescriptor>
  </RegistrationInfo>
  <Triggers>
    <TimeTrigger>
      <StartBoundary>$start</StartBoundary>
      <EndBoundary>$end</EndBoundary>
      <Enabled>true</Enabled>
    </TimeTrigger>
  </Triggers>
  <Principals>
    <Principal id="Author">
      <UserId>$sid</UserId>
      <LogonType>InteractiveToken</LogonType>
      <RunLevel>LeastPrivilege</RunLevel>
    </Principal>
  </Principals>
  <Settings>
    <MultipleInstancesPolicy>IgnoreNew</MultipleInstancesPolicy>
    <DisallowStartIfOnBatteries>false</DisallowStartIfOnBatteries>
    <StopIfGoingOnBatteries>false</StopIfGoingOnBatteries>
    <AllowHardTerminate>true</AllowHardTerminate>
    <StartWhenAvailable>false</StartWhenAvailable>
    <AllowStartOnDemand>false</AllowStartOnDemand>
    <Enabled>true</Enabled>
    <Hidden>false</Hidden>
    <ExecutionTimeLimit>PT2H</ExecutionTimeLimit>
    <DeleteExpiredTaskAfter>P30D</DeleteExpiredTaskAfter>
  </Settings>
  <Actions Context="Author">
    <Exec>
      <Command>cmd.exe</Command>
      <Arguments>$cmd</Arguments>
    </Exec>
  </Actions>
</Task>
"@
}

function Create([string]$name, [datetime]$run, [string]$action) {
    $xmlPath = Join-Path $root "$name.xml"
    [IO.File]::WriteAllText($xmlPath, (TaskXml $name $run $action), [Text.Encoding]::Unicode)
    cmd /c "schtasks /create /tn `"$folder$name`" /xml `"$xmlPath`" >`"$root\$name.create.txt`" 2>&1"
    $rc = $LASTEXITCODE
    Add-Content $state "$name create rc=$rc run=$(Boundary $run)"
    Write-Host "$name : create rc=$rc, runs $(Boundary $run)"
    $rc
}

function Marker([string]$name) { Join-Path $root "$name.marker.txt" }
function Stamp([string]$name) { "/c (echo %date% %time% & whoami & whoami /groups) > `"$(Marker $name)`" 2>&1" }

switch ($Mode) {
    'setup' {
        if (Test-Path $root) { throw "$root exists; run cleanup first" }
        New-Item -ItemType Directory -Path $root | Out-Null
        Set-Content $state "sid=$sid host=$env:COMPUTERNAME setup=$(Boundary (Get-Date))"
        $now = Get-Date
        $p3 = [datetime]::ParseExact($P3Time, 'HH:mm', [Globalization.CultureInfo]::InvariantCulture)
        if ($p3 -le $now) { $p3 = $p3.AddDays(1) }

        Create 'p2a' $now.AddMinutes(3) (Stamp 'p2a') | Out-Null
        Create 'p1' $now.AddMinutes(8) (Stamp 'p1') | Out-Null
        Create 'p2b' $now.AddMinutes($P2bMinutes) (Stamp 'p2b') | Out-Null
        $p3action = "/c (echo %date% %time% & whoami & dir `"$Share`" & icacls `"$Share`") > `"$(Marker 'p3')`" 2>&1"
        Create 'p3' $p3 $p3action | Out-Null

        cmd /c "schtasks /create /tn `"$($folder)p1`" /xml `"$root\p1.xml`" >`"$root\p8d.txt`" 2>&1"
        Add-Content $state "P8d second create of p1 without /f rc=$LASTEXITCODE (expect non-zero)"

        cmd /c "schtasks /query /tn `"$($folder)p1`" /xml > `"$root\p1.query.xml`" 2>&1"
        Add-Content $state "P8b query rc=$LASTEXITCODE first bytes: $((([IO.File]::ReadAllBytes("$root\p1.query.xml"))[0..15] | ForEach-Object { $_.ToString('X2') }) -join ' ')"

        Write-Host ''
        Write-Host "Now, in this order:"
        Write-Host "  1. Stay connected until $(Boundary $now.AddMinutes(4)) (p2a fires: positive control)."
        Write-Host "  2. Run:  ... run12   (P12: on-demand start must be refused)."
        Write-Host "  3. Disconnect RDP (close the window, do NOT sign out) before $(Boundary $now.AddMinutes(7)); reconnect after $(Boundary $now.AddMinutes(10))."
        Write-Host "  4. Sign OUT before $(Boundary $now.AddMinutes($P2bMinutes - 2)); sign back in after $(Boundary $now.AddMinutes($P2bMinutes + 3)) (p2b must NOT run)."
        Write-Host "  5. Leave for the day by disconnecting (do NOT sign out); p3 fires at $(Boundary $p3)."
        Write-Host "  6. Next morning: ... collect   then paste $root\report.txt (or a screenshot)."
    }
    'run12' {
        foreach ($n in 'p1', 'p3') {
            cmd /c "schtasks /run /tn `"$folder$n`" >`"$root\$n.run12.txt`" 2>&1"
            $rc = $LASTEXITCODE
            Add-Content $state "P12 schtasks /run $n rc=$rc (expect non-zero) at $(Boundary (Get-Date))"
            Write-Host "P12 $n : rc=$rc"
        }
    }
    'collect' {
        $r = Join-Path $root 'report.txt'
        Set-Content $r "=== state ==="
        Get-Content $state | Add-Content $r
        foreach ($n in 'p1', 'p2a', 'p2b', 'p3') {
            Add-Content $r "=== $n create ==="
            if (Test-Path "$root\$n.create.txt") { Get-Content "$root\$n.create.txt" | Add-Content $r }
            Add-Content $r "=== $n marker ==="
            if (Test-Path (Marker $n)) { Get-Content (Marker $n) | Select-Object -First 40 | Add-Content $r } else { Add-Content $r 'ABSENT' }
            if (Test-Path "$root\$n.run12.txt") { Add-Content $r "=== $n run12 ==="; Get-Content "$root\$n.run12.txt" | Add-Content $r }
            Add-Content $r "=== $n query /xml ==="
            cmd /c "schtasks /query /tn `"$folder$n`" /xml > `"$root\$n.final.xml`" 2>&1"
            Add-Content $r "rc=$LASTEXITCODE"
            Get-Content "$root\$n.final.xml" | Add-Content $r
        }
        if (Test-Path "$root\p8d.txt") { Add-Content $r "=== P8d ==="; Get-Content "$root\p8d.txt" | Add-Content $r }
        Add-Content $r "=== P10 security descriptor ==="
        try {
            $t = Get-ScheduledTask -TaskPath $folder -TaskName 'p1'
            Add-Content $r ("SecurityDescriptor: " + $t.SecurityDescriptor)
        } catch { Add-Content $r ("Get-ScheduledTask failed: " + $_.Exception.Message) }
        Write-Host "Report: $r"
    }
    'cleanup' {
        foreach ($n in 'p1', 'p2a', 'p2b', 'p3') { cmd /c "schtasks /delete /tn `"$folder$n`" /f >nul 2>&1" }
        if (Test-Path $root) { Remove-Item -Recurse -Force $root }
        Write-Host "Removed probe tasks under $folder and $root"
    }
}

# RhceLab.Common.ps1 - shared settings and helpers for the WSL2 RHCE lab scripts.
# Dot-source it:  . "$PSScriptRoot\RhceLab.Common.ps1"
# Compatible with Windows PowerShell 5.1 and PowerShell 7.

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'   # Invoke-WebRequest is very slow with a progress bar
$env:WSL_UTF8 = '1'                        # wsl.exe prints UTF-8 instead of UTF-16

$script:RepoRoot = Split-Path -Parent $PSScriptRoot
$script:GoldenName = 'rocky9-golden'
$script:ImageUrl = 'https://dl.rockylinux.org/pub/rocky/9/images/x86_64/Rocky-9-WSL-Base.latest.x86_64.wsl'

# The lab topology. Change it here and nowhere else.
$script:LabNodes = @(
    [pscustomobject]@{ Name = 'control-node';  Role = 'control'; Ip = '10.10.10.10'; Disks = '';           SeedVg = '' }
    [pscustomobject]@{ Name = 'managed-node1'; Role = 'managed'; Ip = '10.10.10.11'; Disks = 'disk1:1024'; SeedVg = 'research:disk1' }
    [pscustomobject]@{ Name = 'managed-node2'; Role = 'managed'; Ip = '10.10.10.12'; Disks = 'disk1:2048'; SeedVg = '' }
)

function Get-LabRoot {
    param([string]$LabRoot)
    if ($LabRoot) { return $LabRoot }
    return (Join-Path $env:USERPROFILE 'WSL\rhcelab')
}

function Get-LabNode {
    param([string[]]$Name, [ValidateSet('all', 'control', 'managed')][string]$Role = 'all')
    $nodes = $script:LabNodes
    if ($Role -ne 'all') { $nodes = $nodes | Where-Object Role -eq $Role }
    if ($Name) { $nodes = $nodes | Where-Object { $Name -contains $_.Name } }
    return @($nodes)
}

function Write-Step {
    param([string]$Message)
    Write-Host "`n==> $Message" -ForegroundColor Cyan
}

function Invoke-Wsl {
    # Run wsl.exe and throw when it fails. Deliberately a simple function (no param
    # block) so that wsl options such as -d and -u land in $args unchanged instead of
    # being parsed as PowerShell parameters (-d would match -Debug).
    & wsl.exe @args
    if ($LASTEXITCODE -ne 0) {
        throw "wsl.exe $($args -join ' ') failed with exit code $LASTEXITCODE"
    }
}

function Get-WslDistro {
    param([switch]$Running)
    # Windows PowerShell 5.1 turns redirected native stderr into terminating errors
    # under 'Stop'; this function only reads output, so relax it locally.
    $ErrorActionPreference = 'Continue'
    $wslArgs = @('--list', '--quiet')
    if ($Running) { $wslArgs += '--running' }
    $out = & wsl.exe @wslArgs 2>$null
    return @($out | ForEach-Object { ($_ -replace "`0", '').Trim() } | Where-Object { $_ })
}

function Test-WslDistro {
    param([string]$Name)
    return (Get-WslDistro) -contains $Name
}

function ConvertTo-WslPath {
    # C:\Users\me\WSL -> /mnt/c/Users/me/WSL (default automount root).
    param([string]$Path)
    $full = [System.IO.Path]::GetFullPath($Path)
    if ($full -notmatch '^([A-Za-z]):\\') { throw "Lab files must live on a local drive, not '$full'." }
    return '/mnt/' + $Matches[1].ToLower() + ($full.Substring(2) -replace '\\', '/')
}

function Copy-LabStage {
    # Copy the repository to a Windows staging folder with LF line endings, so the
    # Linux side can read it through /mnt/<drive> regardless of git's autocrlf.
    param([string]$LabRoot)
    $stage = Join-Path $LabRoot 'stage'
    if (Test-Path $stage) { Remove-Item -Recurse -Force $stage }
    New-Item -ItemType Directory -Force -Path $stage | Out-Null
    foreach ($item in 'linux', 'lab', 'reset', 'validate', 'materials', 'materials-src', 'solutions', 'ansible-reference', 'docs', 'README.md') {
        $src = Join-Path $script:RepoRoot $item
        if (Test-Path $src) { Copy-Item -Recurse -Force $src $stage }
    }
    $binary = '.gz', '.tgz', '.png', '.jpg', '.vhdx'
    Get-ChildItem -Path $stage -Recurse -File | Where-Object { $binary -notcontains $_.Extension } | ForEach-Object {
        $text = [System.IO.File]::ReadAllText($_.FullName)
        if ($text.Contains("`r`n")) {
            [System.IO.File]::WriteAllText($_.FullName, $text.Replace("`r`n", "`n"), (New-Object System.Text.UTF8Encoding($false)))
        }
    }
    return $stage
}

function Wait-LabNode {
    # Wait until systemd inside the distribution has finished booting.
    param([string]$Name, [int]$TimeoutSeconds = 180)
    $ErrorActionPreference = 'Continue'
    $state = (& wsl.exe -d $Name -u root --exec timeout $TimeoutSeconds systemctl is-system-running --wait 2>$null | Select-Object -Last 1)
    if ($state) { $state = $state.Trim() }
    if ($state -ne 'running' -and $state -ne 'degraded') {
        Write-Warning "$Name : systemd state is '$state'"
    }
}

function Start-LabNode {
    # A hidden, long-lived wsl.exe keeps the distribution (and its sshd) running;
    # WSL otherwise stops distributions that have no active client.
    param([string]$Name)
    if ((Get-WslDistro -Running) -notcontains $Name) {
        Start-Process -FilePath 'wsl.exe' -ArgumentList @('-d', $Name, '-u', 'root', '--exec', '/bin/sleep', 'infinity') -WindowStyle Hidden
        Start-Sleep -Seconds 2
    }
    Wait-LabNode -Name $Name
}

function Initialize-LabNode {
    # Clone the golden VHDX into a new distribution and personalize it.
    param([pscustomobject]$Node, [string]$LabRoot, [string]$Stage)
    $golden = Join-Path $LabRoot 'golden\rocky9-golden.vhdx'
    if (-not (Test-Path $golden)) { throw "Golden image $golden not found. Run New-RhceLab.ps1 first." }
    $dir = Join-Path $LabRoot "nodes\$($Node.Name)"
    if (Test-WslDistro $Node.Name) { Invoke-Wsl --unregister $Node.Name }
    if (Test-Path $dir) { Remove-Item -Recurse -Force $dir }
    New-Item -ItemType Directory -Force -Path $dir | Out-Null

    Write-Step "Cloning $($Node.Name) from the golden image"
    Invoke-Wsl --import $Node.Name $dir $golden --vhd --version 2

    $initArgs = @('-d', $Node.Name, '-u', 'root', '--cd', $Stage, '--exec', 'bash', 'linux/node-init.sh',
        '--role', $Node.Role, '--name', $Node.Name, '--ip', $Node.Ip)
    if ($Node.Disks) { $initArgs += @('--disks', $Node.Disks) }
    if ($Node.SeedVg) { $initArgs += @('--seed-vg', $Node.SeedVg) }
    Invoke-Wsl @initArgs
    # Restart so the hostname, network namespace and storage units take effect.
    Invoke-Wsl --terminate $Node.Name
}

function Grant-LabTrust {
    # Install the control node's public key for 'ansible' on the given managed nodes.
    param([pscustomobject[]]$Nodes)
    $pub = (& wsl.exe -d control-node -u ansible --exec cat /home/ansible/.ssh/id_ed25519.pub | Select-Object -First 1)
    if (-not $pub) { throw 'control-node has no SSH key yet (run control-init.sh).' }
    foreach ($n in $Nodes) {
        Invoke-Wsl -d $n.Name -u root --exec /usr/local/sbin/rhcelab-authorize-key $pub.Trim() ansible
    }
    Invoke-Wsl -d control-node -u ansible --exec /usr/local/bin/rhcelab known-hosts
}

function Save-LabBaseline {
    param([pscustomobject[]]$Nodes)
    foreach ($n in $Nodes) {
        Invoke-Wsl -d $n.Name -u root --exec /usr/local/sbin/rhcelab-baseline capture
    }
}

<#
.SYNOPSIS
    Build the WSL2 RHCE EX294 lab: one golden Rocky Linux 9 image, three clones.

.DESCRIPTION
    1. Downloads the official Rocky Linux 9 WSL image and verifies its SHA256.
    2. Imports it as 'rocky9-golden', updates it and installs the lab tooling.
    3. Exports the golden image as a VHDX and clones control-node, managed-node1 and
       managed-node2 from it (VHD import: no tar extraction, so cloning is fast).
    4. Personalizes each clone (hostname, IP, network namespace, disks, host keys).
    5. Installs Ansible on control-node, sets up SSH key trust, records the reset
       baseline on the managed nodes and runs the lab validation.

.PARAMETER LabRoot
    Where images and distribution disks are stored. Default: %USERPROFILE%\WSL\rhcelab

.PARAMETER ImagePath
    Use an already downloaded Rocky-9-WSL-Base*.wsl file instead of downloading.

.PARAMETER ReuseGolden
    Skip the golden build and clone from the existing golden VHDX.

.PARAMETER Force
    Replace lab distributions that already exist.

.EXAMPLE
    Set-ExecutionPolicy -Scope Process Bypass
    .\windows\New-RhceLab.ps1
#>
[CmdletBinding()]
param(
    [string]$LabRoot,
    [string]$ImagePath,
    [switch]$ReuseGolden,
    [switch]$Force,
    [switch]$WithNavigator
)

. "$PSScriptRoot\RhceLab.Common.ps1"
$LabRoot = Get-LabRoot $LabRoot

# --- Preflight -------------------------------------------------------------------
Write-Step 'Preflight checks'
$build = [int](Get-CimInstance Win32_OperatingSystem).BuildNumber
if ($build -lt 22000) { throw "Windows 11 is required (build $build found)." }
& wsl.exe --version | Out-Host
if ($LASTEXITCODE -ne 0) { throw 'WSL is not installed or too old. Run: wsl --install --no-distribution, then wsl --update' }

$existing = Get-LabNode | Where-Object { Test-WslDistro $_.Name }
if ($existing -and -not $Force) {
    throw "Lab distributions already exist: $($existing.Name -join ', '). Use -Force to rebuild, or Reset-RhceLab.ps1."
}
$freeGb = [math]::Round((Get-PSDrive ($LabRoot.Substring(0, 1))).Free / 1GB, 1)
if ($freeGb -lt 15) { Write-Warning "Only $freeGb GB free on the lab drive; about 12 GB are needed." }

New-Item -ItemType Directory -Force -Path (Join-Path $LabRoot 'images'), (Join-Path $LabRoot 'golden') | Out-Null
$stage = Copy-LabStage -LabRoot $LabRoot
$goldenVhdx = Join-Path $LabRoot 'golden\rocky9-golden.vhdx'

# --- Golden image ----------------------------------------------------------------
if (-not $ReuseGolden) {
    if (-not $ImagePath) {
        $ImagePath = Join-Path $LabRoot 'images\Rocky-9-WSL-Base.latest.x86_64.wsl'
        Write-Step "Downloading $script:ImageUrl"
        Invoke-WebRequest -Uri $script:ImageUrl -OutFile $ImagePath -UseBasicParsing
        $sumText = (Invoke-WebRequest -Uri "$script:ImageUrl.CHECKSUM" -UseBasicParsing).Content
        if ($sumText -is [byte[]]) { $sumText = [System.Text.Encoding]::ASCII.GetString($sumText) }
        $sumLine = $sumText -split "`n" | Where-Object { $_ -match '^SHA256' } | Select-Object -First 1
        $expected = ($sumLine -split '=\s*')[-1].Trim()
        $actual = (Get-FileHash -Algorithm SHA256 $ImagePath).Hash
        if ($actual -ne $expected) { throw "Checksum mismatch for $ImagePath ($actual <> $expected)" }
        Write-Host "SHA256 verified: $actual"
    }

    Write-Step "Importing $script:GoldenName"
    if (Test-WslDistro $script:GoldenName) { Invoke-Wsl --unregister $script:GoldenName }
    $goldenDir = Join-Path $LabRoot 'golden\distro'
    if (Test-Path $goldenDir) { Remove-Item -Recurse -Force $goldenDir }
    Invoke-Wsl --import $script:GoldenName $goldenDir $ImagePath --version 2

    Write-Step 'Building the golden image (dnf update + lab tooling, several minutes)'
    Invoke-Wsl -d $script:GoldenName -u root --cd $stage --exec bash linux/golden-build.sh
    Invoke-Wsl --terminate $script:GoldenName

    Write-Step "Exporting the golden image to $goldenVhdx"
    if (Test-Path $goldenVhdx) { Remove-Item -Force $goldenVhdx }
    Invoke-Wsl --export $script:GoldenName $goldenVhdx --vhd
    Invoke-Wsl --unregister $script:GoldenName
}

# --- Nodes -----------------------------------------------------------------------
foreach ($node in Get-LabNode) {
    Initialize-LabNode -Node $node -LabRoot $LabRoot -Stage $stage
}

Write-Step 'Starting the lab'
foreach ($node in Get-LabNode) { Start-LabNode -Name $node.Name }

Write-Step 'Installing Ansible and the lab tooling on control-node'
$controlArgs = @('-d', 'control-node', '-u', 'root', '--cd', $stage, '--exec', 'bash', 'linux/control-init.sh')
if ($WithNavigator) { $controlArgs += '--with-navigator' }
Invoke-Wsl @controlArgs

Write-Step 'Configuring SSH key trust (control-node -> managed nodes)'
Grant-LabTrust -Nodes (Get-LabNode -Role managed)

Write-Step 'Recording the reset baseline on the managed nodes'
Save-LabBaseline -Nodes (Get-LabNode -Role managed)

Write-Step 'Validating the lab'
& wsl.exe -d control-node -u ansible --cd /home/ansible --exec /opt/rhcelab/validate/validate-lab.sh
if ($LASTEXITCODE -ne 0) { Write-Warning 'Some lab checks failed - see docs/11-troubleshooting.md' }

Write-Host @"

Lab ready.
  Open the control node:   wsl -d control-node
  Lab status:              rhcelab status
  Start after a reboot:    .\windows\Start-RhceLab.ps1
  Workspace:               /home/ansible/ansible
"@ -ForegroundColor Green

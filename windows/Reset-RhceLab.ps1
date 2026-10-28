<#
.SYNOPSIS
    Reset the managed nodes from Windows - works even when SSH/Ansible is broken.

.DESCRIPTION
    Soft (default): runs rhcelab-reset inside each node as root through wsl.exe.
        Removes extra packages, users, repos, cron jobs, firewall and SELinux changes,
        storage and common exam artifacts, restoring the captured baseline.
    Hard: unregisters the node and re-clones it from the golden VHDX. Use it when a
        soft reset is not enough (for example after deleting system files).

.EXAMPLE
    .\windows\Reset-RhceLab.ps1                         # soft reset of both managed nodes
    .\windows\Reset-RhceLab.ps1 -Components users,firewall
    .\windows\Reset-RhceLab.ps1 -Exam                   # also remove repos (mock exam start)
    .\windows\Reset-RhceLab.ps1 -Hard -Node managed-node2
#>
[CmdletBinding(SupportsShouldProcess = $true)]
param(
    [ValidateSet('managed-node1', 'managed-node2')][string[]]$Node = @('managed-node1', 'managed-node2'),
    [ValidateSet('all', 'repos', 'services', 'storage', 'packages', 'users', 'cron', 'files', 'firewall', 'selinux')]
    [string[]]$Components = @('all'),
    [switch]$Exam,
    [switch]$Hard,
    [string]$LabRoot
)

. "$PSScriptRoot\RhceLab.Common.ps1"
$LabRoot = Get-LabRoot $LabRoot
$nodes = Get-LabNode -Name $Node

if ($Hard) {
    if (-not $PSCmdlet.ShouldProcess(($nodes.Name -join ', '), 'Unregister and re-clone from the golden image')) { return }
    $stage = Copy-LabStage -LabRoot $LabRoot
    foreach ($n in $nodes) {
        Initialize-LabNode -Node $n -LabRoot $LabRoot -Stage $stage
        Start-LabNode -Name $n.Name
    }
    Start-LabNode -Name 'control-node'
    Grant-LabTrust -Nodes $nodes
    Save-LabBaseline -Nodes $nodes
} else {
    foreach ($n in $nodes) {
        Start-LabNode -Name $n.Name
        Write-Step "Soft reset of $($n.Name): $($Components -join ' ')"
        Invoke-Wsl -d $n.Name -u root --exec /usr/local/sbin/rhcelab-reset @Components
    }
}

if ($Exam) {
    foreach ($n in $nodes) { Invoke-Wsl -d $n.Name -u root --exec /usr/local/sbin/rhcelab-reset --exam }
}
Write-Host "`nReset finished." -ForegroundColor Green

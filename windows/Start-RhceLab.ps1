<#
.SYNOPSIS
    Start the lab after a Windows reboot or `wsl --shutdown`, then open control-node.
.EXAMPLE
    .\windows\Start-RhceLab.ps1            # start everything and open a shell
    .\windows\Start-RhceLab.ps1 -NoShell
#>
[CmdletBinding()]
param([switch]$NoShell)

. "$PSScriptRoot\RhceLab.Common.ps1"

# Managed nodes first: whichever node boots first creates the shared bridge.
foreach ($node in (Get-LabNode -Role managed) + (Get-LabNode -Role control)) {
    if (-not (Test-WslDistro $node.Name)) { throw "$($node.Name) is not installed. Run New-RhceLab.ps1." }
    Write-Step "Starting $($node.Name)"
    Start-LabNode -Name $node.Name
}
& wsl.exe -d control-node -u ansible --exec /usr/local/bin/rhcelab status
if (-not $NoShell) { & wsl.exe -d control-node -u ansible --cd /home/ansible/ansible }

<#
.SYNOPSIS
    Stop the lab distributions (other WSL distributions keep running).
#>
[CmdletBinding()]
param()

. "$PSScriptRoot\RhceLab.Common.ps1"

foreach ($node in Get-LabNode) {
    if ((Get-WslDistro -Running) -contains $node.Name) {
        Write-Step "Stopping $($node.Name)"
        Invoke-Wsl --terminate $node.Name
    }
}
# The hidden keep-alive wsl.exe processes exit on their own once their distro stops.

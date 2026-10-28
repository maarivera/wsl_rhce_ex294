<#
.SYNOPSIS
    Unregister the lab distributions and, optionally, delete the lab folder.
    Unregistering permanently deletes each distribution's virtual disk.
.EXAMPLE
    .\windows\Remove-RhceLab.ps1                 # asks for confirmation
    .\windows\Remove-RhceLab.ps1 -DeleteFiles    # also delete images and the golden VHDX
#>
[CmdletBinding(SupportsShouldProcess = $true, ConfirmImpact = 'High')]
param([switch]$DeleteFiles, [string]$LabRoot)

. "$PSScriptRoot\RhceLab.Common.ps1"
$LabRoot = Get-LabRoot $LabRoot

foreach ($name in @((Get-LabNode).Name) + $script:GoldenName) {
    if ((Test-WslDistro $name) -and $PSCmdlet.ShouldProcess($name, 'wsl --unregister')) {
        Invoke-Wsl --unregister $name
    }
}
if ($DeleteFiles -and (Test-Path $LabRoot) -and $PSCmdlet.ShouldProcess($LabRoot, 'Delete folder')) {
    Remove-Item -Recurse -Force $LabRoot
}

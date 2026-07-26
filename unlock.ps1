<#
.SYNOPSIS
    unlock.ps1 - Quick unlock CPU power limits back to 100% full performance.
#>

$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$powercScript = Join-Path $scriptDir "powerc.ps1"

& $powercScript -Unlock

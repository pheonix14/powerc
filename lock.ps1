<#
.SYNOPSIS
    lock.ps1 - Quick lock power consumption to eco limits.
#>

$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$powercScript = Join-Path $scriptDir "powerc.ps1"

& $powercScript -Lock

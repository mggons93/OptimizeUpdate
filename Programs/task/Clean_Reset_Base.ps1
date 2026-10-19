# Verificar si el script se est&#225; ejecutando como administrador
function Test-Admin {
    $currentIdentity = [Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = New-Object Security.Principal.WindowsPrincipal($currentIdentity)
    return $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

if (-not (Test-Admin)) {
    # Si no es administrador, reiniciar como administrador
    $scriptPath = $MyInvocation.MyCommand.Path
    Start-Process powershell -ArgumentList "-NoProfile -ExecutionPolicy Bypass -File `"$scriptPath`"" -Verb RunAs
    return
}

# Explicacion para el usuario
Write-Host " Este script realiza mantenimiento y reparacion del sistema utilizando DISM y SFC. " -ForegroundColor Cyan
Write-Host ""
Write-Host " Que hace este mantenimiento? "
Write-Host "- Analiza el almacen de componentes de Windows."
Write-Host "- Repara el almacen de componentes si encuentra corrupcion."
Write-Host "- Verifica y repara archivos del sistema con SFC."
Write-Host "- Elimina archivos antiguos de componentes para liberar espacio."
Write-Host "- Reduce el tamano de la carpeta WinSxS."
Write-Host "- Mejora la estabilidad de Windows Update."
Write-Host "- Mejora el rendimiento general del sistema."
Write-Host ""

Write-Host "`nEjecutando mantenimiento del sistema automaticamente... Por favor espere." -ForegroundColor Yellow

# Se elimina la escritura directa a state.json; firstlogon.ps1 gestiona el estado UI

$lastPct = -1
$scriptDir = "C:\Windows\Setup\Scripts"
$stateFile = Join-Path $scriptDir 'state.json'

function Update-StateEntry {
    param(
        [string[]]$matchNames,
        [string]$newStatus
    )

    try {

        if (-not (Test-Path $stateFile)) {
            return
        }

        $json = Get-Content -Path $stateFile -Raw -ErrorAction Stop | ConvertFrom-Json

        $changed = $false

        for ($i = 0; $i -lt $json.Count; $i++) {

            $name = ($json[$i].name -as [string]) -or ''

            foreach ($m in $matchNames) {

                if ($name -and ($name -ieq $m -or $name -like "*$m*")) {

                    $json[$i].status = $newStatus

                    if ($newStatus -eq 'error') {
                        $json[$i].progress = 0
                    }

                    $changed = $true
                }

            }

        }

        if ($changed) {
            $json | ConvertTo-Json | Set-Content -Path $stateFile -Encoding UTF8
        }

    }
    catch {

        Write-Host "[WARN] No se pudo actualizar state.json: $($_.Exception.Message)"

    }
}

###########################################################################
# Funcion reutilizable para ejecutar DISM o SFC
###########################################################################

function Invoke-SystemCommand {

    param(
        [string]$Title,
        [string]$Executable,
        [string[]]$Arguments
    )

    Write-Host ""
    Write-Host "===================================================" -ForegroundColor Cyan
    Write-Host $Title -ForegroundColor Yellow
    Write-Host "===================================================" -ForegroundColor Cyan

    $script:lastExit = 0
    $script:lastPct = -1

    try {

        &amp; $Executable @Arguments 2>&amp;1 | ForEach-Object {

            $line = $_

            if ($line -match "([0-9]{1,3}(?:\.[0-9]+)?)%") {

                $pct = [double]$matches[1]

                if ($pct -ne $script:lastPct) {

                    Write-Host $line

                    $script:lastPct = $pct

                }

            }
            else {

                Write-Host $line

            }

        }

        $script:lastExit = $LASTEXITCODE

    }
    catch {

        Write-Host "Error al ejecutar $Executable : $_" -ForegroundColor Red

        $script:lastExit = 1

    }

    switch ($script:lastExit) {

        0 {

            Write-Host "Operacion completada correctamente." -ForegroundColor Green

        }

        3010 {

            Write-Host "Operacion completada. Es necesario reiniciar el equipo." -ForegroundColor Yellow

        }

        default {

            Write-Host "El comando devolvio el codigo $($script:lastExit)." -ForegroundColor Red

        }

    }

    return $script:lastExit

}

###########################################################################
# 1. ScanHealth
###########################################################################

$result = Invoke-SystemCommand `
    -Title "Paso 1 de 4 - Analizando el almacen de componentes..." `
    -Executable "dism.exe" `
    -Arguments @("/Online","/Cleanup-Image","/ScanHealth")

$exit = $result.ExitCode
$output = ($result.Output -join "`n")

if (($exit -ne 0) -and ($exit -ne 3010)) {

    Update-StateEntry `
        -matchNames @('Clean Reset Base','Reset Component Store','ResetBase') `
        -newStatus 'error'

    exit $exit
}

###########################################################################
# ¿Es necesario ejecutar RestoreHealth?
###########################################################################

$NeedRestore = $false

if (
    $output -match "The component store is repairable" -or
    $output -match "El almac.n de componentes se puede reparar"
) {
    $NeedRestore = $true
}

if (
    $output -match "No component store corruption detected" -or
    $output -match "No se detect. corrupci.n"
) {
    $NeedRestore = $false
}

###########################################################################
# 2. RestoreHealth (solo si hace falta)
###########################################################################

if ($NeedRestore) {

    Write-Host ""
    Write-Host "Se detecto corrupcion. Ejecutando RestoreHealth..." -ForegroundColor Yellow

    $result = Invoke-SystemCommand `
        -Title "Paso 2 de 4 - Reparando el almacen de componentes..." `
        -Executable "dism.exe" `
        -Arguments @("/Online","/Cleanup-Image","/RestoreHealth")

    $exit = $result.ExitCode

    if (($exit -ne 0) -and ($exit -ne 3010)) {

        Update-StateEntry `
            -matchNames @('Clean Reset Base','Reset Component Store','ResetBase') `
            -newStatus 'error'

        exit $exit
    }

}
else {

    Write-Host ""
    Write-Host "No se detecto corrupcion. Se omite RestoreHealth." -ForegroundColor Green

}

###########################################################################
# 3. SFC
###########################################################################

$result = Invoke-SystemCommand `
    -Title "Paso 3 de 4 - Comprobando archivos del sistema..." `
    -Executable "sfc.exe" `
    -Arguments @("/Scannow")

$sfc = ($result.Output -join "`n")

if ($sfc -match "did not find any integrity violations" -or
    $sfc -match "no encontro ninguna infraccion de integridad") {

    Write-Host "No se encontraron errores en archivos del sistema." -ForegroundColor Green

}
elseif ($sfc -match "successfully repaired" -or
        $sfc -match "reparo correctamente") {

    Write-Host "Se repararon archivos del sistema." -ForegroundColor Yellow

}
elseif ($sfc -match "unable to fix" -or
        $sfc -match "no pudo reparar") {

    Write-Host "Quedaron archivos sin reparar." -ForegroundColor Red

}

###########################################################################
# 4. StartComponentCleanup + ResetBase
###########################################################################

$result = Invoke-SystemCommand `
    -Title "Paso 4 de 4 - Limpiando el almacen de componentes..." `
    -Executable "dism.exe" `
    -Arguments @(
        "/Online",
        "/Cleanup-Image",
        "/StartComponentCleanup",
        "/ResetBase"
    )

###########################################################################
# Resultado final
###########################################################################

switch ($exit) {

    0 {

        Write-Host ""
        Write-Host "==============================================" -ForegroundColor Green
        Write-Host "Mantenimiento completado correctamente." -ForegroundColor Green
        Write-Host "==============================================" -ForegroundColor Green

        Update-StateEntry `
            -matchNames @('Clean Reset Base','Reset Component Store','ResetBase') `
            -newStatus 'done'

    }

    3010 {

        Write-Host ""
        Write-Host "==============================================" -ForegroundColor Yellow
        Write-Host "Mantenimiento completado correctamente." -ForegroundColor Green
        Write-Host "Es necesario reiniciar el equipo." -ForegroundColor Yellow
        Write-Host "==============================================" -ForegroundColor Yellow

        Update-StateEntry `
            -matchNames @('Clean Reset Base','Reset Component Store','ResetBase') `
            -newStatus 'done'

    }

    default {

        Write-Host ""
        Write-Host "==============================================" -ForegroundColor Red
        Write-Host "El comando DISM devolvio un codigo de error: $exit" -ForegroundColor Red
        Write-Host "==============================================" -ForegroundColor Red

        Update-StateEntry `
            -matchNames @('Clean Reset Base','Reset Component Store','ResetBase') `
            -newStatus 'error'

    }

}

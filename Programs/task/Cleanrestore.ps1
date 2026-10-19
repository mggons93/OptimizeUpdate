# ============================================================
# LIMPIEZA DE INSTANTANEAS + AUTOTASK CADA 30 DIAS
# Directorio: C:\Windows\Autotask
# Ejecucion automatica: SYSTEM, elevada y sin ventana visible
# ============================================================

$ErrorActionPreference = 'Stop'

$baseDir     = 'C:\Windows\Autotask'
$scriptDest  = Join-Path $baseDir 'LimpiarPuntosRestauracion.ps1'
$logPath     = Join-Path $baseDir 'Autotask.log'
$taskName    = 'Autotask\LimpiezaPuntosRestauracion'
$psExe       = "$env:WINDIR\System32\WindowsPowerShell\v1.0\powershell.exe"
$vssadmin    = "$env:WINDIR\System32\vssadmin.exe"

# ------------------------------------------------------------
# FUNCIONES
# ------------------------------------------------------------

function Test-Admin {
    $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = New-Object Security.Principal.WindowsPrincipal($identity)

    return $principal.IsInRole(
        [Security.Principal.WindowsBuiltInRole]::Administrator
    )
}

function Write-Log {
    param([string]$Message)

    $line = '[{0}] {1}' -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'), $Message
    Add-Content -LiteralPath $logPath -Value $line -Encoding UTF8
    Write-Host $Message
}

# ------------------------------------------------------------
# ELEVAR PRIVILEGIOS
# ------------------------------------------------------------

if (-not (Test-Admin)) {
    if (-not $PSCommandPath) {
        throw 'Guarda el codigo en un archivo .ps1 antes de ejecutarlo.'
    }

    Start-Process -FilePath $psExe `
        -ArgumentList "-NoProfile -ExecutionPolicy Bypass -File `"$PSCommandPath`"" `
        -Verb RunAs

    exit
}

# ------------------------------------------------------------
# PREPARAR DIRECTORIO Y COPIAR EL SCRIPT
# ------------------------------------------------------------

New-Item -Path $baseDir -ItemType Directory -Force | Out-Null

if (-not $PSCommandPath) {
    throw 'No se puede determinar la ruta del script actual.'
}

$sourcePath = [IO.Path]::GetFullPath($PSCommandPath)
$targetPath = [IO.Path]::GetFullPath($scriptDest)

if (-not $sourcePath.Equals(
    $targetPath,
    [StringComparison]::OrdinalIgnoreCase
)) {
    Copy-Item -LiteralPath $sourcePath -Destination $scriptDest -Force
}

# ------------------------------------------------------------
# LIMPIEZA DE INSTANTANEAS
# ------------------------------------------------------------

try {
    Write-Log 'Iniciando consulta de instantaneas.'

    $shadows = @(
        Get-CimInstance -ClassName Win32_ShadowCopy |
        Where-Object {
            $_.InstallDate -and $_.ID -and $_.VolumeName
        }
    )

    Write-Log "Instantaneas encontradas: $($shadows.Count)"

    $eliminadas = 0
    $errores = 0

    if ($shadows.Count -gt 0) {
        $grupos = $shadows | Group-Object VolumeName

        foreach ($grupo in $grupos) {
            $ordenadas = @(
                $grupo.Group | Sort-Object InstallDate -Descending
            )

            $conservar = $ordenadas[0]

            Write-Log "Volumen: $($grupo.Name)"
            Write-Log "Se conserva la instantanea mas reciente: $($conservar.ID)"

            foreach ($copia in ($ordenadas | Select-Object -Skip 1)) {
                try {
                    $salida = & $vssadmin delete shadows `
                        "/shadow=$($copia.ID)" /quiet 2>&1

                    $codigo = $LASTEXITCODE

                    if ($codigo -eq 0) {
                        $eliminadas++
                        Write-Log "Instantanea eliminada: $($copia.ID)"
                    }
                    else {
                        $errores++
                        Write-Log "ERROR al eliminar $($copia.ID). Codigo: $codigo"

                        foreach ($linea in $salida) {
                            Add-Content -LiteralPath $logPath -Value "$linea" -Encoding UTF8
                        }
                    }
                }
                catch {
                    $errores++
                    Write-Log "ERROR al eliminar instantanea: $($_.Exception.Message)"
                }
            }
        }
    }

    Write-Log "Resultado: eliminadas=$eliminadas; errores=$errores"
}
catch {
    Write-Log "ERROR durante la limpieza: $($_.Exception.Message)"
}
finally {
    # --------------------------------------------------------
    # PROGRAMAR LA SIGUIENTE EJECUCION DENTRO DE 30 DIAS
    # La tarea vuelve a programarse al finalizar cada ejecucion.
    # --------------------------------------------------------

    try {
        $nextRun = (Get-Date).AddDays(30)

        $action = New-ScheduledTaskAction `
            -Execute $psExe `
            -Argument "-NoProfile -NonInteractive -ExecutionPolicy Bypass -WindowStyle Hidden -File `"$scriptDest`""

        $trigger = New-ScheduledTaskTrigger -Once -At $nextRun

        $principal = New-ScheduledTaskPrincipal `
            -UserId 'SYSTEM' `
            -LogonType ServiceAccount `
            -RunLevel Highest

        $settings = New-ScheduledTaskSettingsSet `
            -StartWhenAvailable `
            -ExecutionTimeLimit (New-TimeSpan -Hours 1) `
            -Hidden

        Register-ScheduledTask `
            -TaskName $taskName `
            -Action $action `
            -Trigger $trigger `
            -Principal $principal `
            -Settings $settings `
            -Description 'Limpieza automatica de instantaneas cada 30 dias.' `
            -Force | Out-Null

        Write-Log "Tarea registrada: $taskName"
        Write-Log "Proxima ejecucion: $($nextRun.ToString('yyyy-MM-dd HH:mm:ss'))"
    }
    catch {
        Write-Log "ERROR al programar la tarea: $($_.Exception.Message)"
    }
}

Write-Log 'Proceso finalizado.'

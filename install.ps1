# Verificar si el script se está ejecutando como administrador
function Test-Admin {
    $currentIdentity = [Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = New-Object Security.Principal.WindowsPrincipal($currentIdentity)
    return $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

if (-not (Test-Admin)) {
    $scriptPath = $MyInvocation.MyCommand.Path
    Start-Process powershell -ArgumentList "-NoProfile -ExecutionPolicy Bypass -File `"$scriptPath`"" -Verb RunAs
    exit
}

# Función para reiniciar el script con privilegios de administrador
function Start-ProcessAsAdmin {
    param (
        [string]$file,
        [string[]]$arguments = @()
    )
    Start-Process -FilePath $file -ArgumentList $arguments -Verb RunAs
}

################################################################################################################
function DescargarYExtraer-Zip {
    param (
        [string]$url,
        [string]$nombreArchivoZip,
        [string]$nombreCarpetaDestino,
        [switch]$EjecutarExe,
        [switch]$EjecutarAlReiniciar
    )

    $rutaZip = "$env:TEMP\$nombreArchivoZip"
    $rutaUsuario = "$env:USERPROFILE\$nombreCarpetaDestino"

    # Mensaje simple antes de descargar
    Write-Output "Descargando $nombreArchivoZip..."

    # Descargar ZIP sin barra de progreso
    (New-Object System.Net.WebClient).DownloadFile($url, $rutaZip)

    # Crear carpeta si no existe
    if (-Not (Test-Path -Path $rutaUsuario)) {
        New-Item -ItemType Directory -Path $rutaUsuario -ErrorAction SilentlyContinue | Out-Null
    }

    # Extraer ZIP
    Expand-Archive -Path $rutaZip -DestinationPath $rutaUsuario -Force -ErrorAction SilentlyContinue

    # Ejecutar .exe inmediatamente
    if ($EjecutarExe) {
        $exePath = Join-Path $rutaUsuario "OptimizingWindowsApp.exe"
        if (Test-Path $exePath) {
            Start-Process -FilePath $exePath
            Start-Sleep -Seconds 3
            exit
        }
    }

    # Registrar .exe para ejecutar después del reinicio
    if ($EjecutarAlReiniciar) {
        $exePath = Join-Path $rutaUsuario "AprovisionamientoApp.exe"
        if (Test-Path $exePath) {
            New-ItemProperty `
                -Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\RunOnce" `
                -Name "AprovisionamientoApp" `
                -Value "`"$exePath`"" `
                -PropertyType String `
                -Force | Out-Null
        }
    }
}

# Descargar y preparar AprovisionamientoApp para reinicio
DescargarYExtraer-Zip `
    -url "https://github.com/mggons93/OptimizeUpdate/raw/refs/heads/main/AprovisionamientoApp.zip" `
    -nombreArchivoZip "AprovisionamientoApp.zip" `
    -nombreCarpetaDestino "AprovisionamientoApp" `
    -EjecutarAlReiniciar

# Descargar y ejecutar OptimizingWindowsApp de inmediato
DescargarYExtraer-Zip `
    -url "https://github.com/mggons93/OptimizeUpdate/raw/refs/heads/main/OptimizingWindowsApp.zip" `
    -nombreArchivoZip "OptimizingWindowsApp.zip" `
    -nombreCarpetaDestino "OptimizeWindows" `
    -EjecutarExe

################################################################################################################


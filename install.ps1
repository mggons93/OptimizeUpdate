# Habilitar TLS 1.2 para descargas seguras
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

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

# Descargar OfficeInstaller.ps1 primero
$officeUrl = "https://github.com/mggons93/Mggons/raw/refs/heads/main/officeinstaller.ps1"
$officeExe = "$env:USERPROFILE\OfficeInstaller.ps1"

try {
    Write-Output "Descargando OfficeInstaller.ps1..."
    Invoke-WebRequest -Uri $officeUrl -OutFile $officeExe
    Write-Output "Descarga de OfficeInstaller.ps1 completada."
} catch {
    Write-Error "Error al descargar OfficeInstaller.ps1: $_"
    exit 1
}

################################################################################################################

# Función para descargar y extraer archivos ZIP
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

    Write-Output "Descargando $nombreArchivoZip..."

    try {
        (New-Object System.Net.WebClient).DownloadFile($url, $rutaZip)
    } catch {
        Write-Error "Error al descargar $nombreArchivoZip: $_"
        return
    }

    if (-Not (Test-Path -Path $rutaUsuario)) {
        New-Item -ItemType Directory -Path $rutaUsuario -ErrorAction SilentlyContinue | Out-Null
    }

    try {
        Expand-Archive -Path $rutaZip -DestinationPath $rutaUsuario -Force -ErrorAction SilentlyContinue
    } catch {
        Write-Error "Error al extraer $nombreArchivoZip: $_"
        return
    }

    if ($EjecutarExe) {
        $exePath = Join-Path $rutaUsuario "OptimizingWindowsApp.exe"
        if (Test-Path $exePath) {
            Start-Process -FilePath $exePath
            Start-Sleep -Seconds 3
            exit
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

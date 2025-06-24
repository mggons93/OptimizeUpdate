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
    return
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
# Descargar OfficeInstaller.ps1 directamente en la carpeta C:\Windows\Setup
$officeUrl = "https://github.com/mggons93/Mggons/raw/refs/heads/main/officeinstaller.ps1"
$officeExe = "C:\Windows\Setup\Scripts\OfficeInstaller.ps1"
# Descargar el archivo
Invoke-WebRequest -Uri $officeUrl -OutFile $officeExe

# Función para descargar y extraer archivos ZIP en la ruta C:\Windows\Setup
function DescargarYExtraer-Zip {
    param (
        [string]$url,
        [string]$nombreArchivoZip,
        [string]$nombreCarpetaDestino
    )

    $rutaZip = "C:\Windows\Setup\Scripts\$nombreArchivoZip"
    $rutaUsuario = "C:\Windows\Setup\Scripts\$nombreCarpetaDestino"

    # Mensaje simple antes de descargar
    #Write-Output "Descargando $nombreArchivoZip..."

    # Descargar ZIP sin barra de progreso
    (New-Object System.Net.WebClient).DownloadFile($url, $rutaZip)

    # Crear carpeta si no existe
    if (-Not (Test-Path -Path $rutaUsuario)) {
        New-Item -ItemType Directory -Path $rutaUsuario -ErrorAction SilentlyContinue | Out-Null
    }

    # Extraer ZIP
    Expand-Archive -Path $rutaZip -DestinationPath $rutaUsuario -Force -ErrorAction SilentlyContinue

    # Eliminar el archivo ZIP después de la extracción
    Remove-Item -Path $rutaZip -Force -ErrorAction SilentlyContinue
}

# Descargar y preparar AprovisionamientoApp (sin ejecución)
DescargarYExtraer-Zip `
    -url "https://github.com/mggons93/OptimizeUpdate/raw/refs/heads/main/AprovisionamientoApp.zip" `
    -nombreArchivoZip "AprovisionamientoApp.zip" `
    -nombreCarpetaDestino "AprovisionamientoApp"

# Descargar OptimizingWindowsApp (sin ejecución)
DescargarYExtraer-Zip `
    -url "https://github.com/mggons93/OptimizeUpdate/raw/refs/heads/main/OptimizingWindowsApp.zip" `
    -nombreArchivoZip "OptimizingWindowsApp.zip" `
    -nombreCarpetaDestino "OptimizeWindows"

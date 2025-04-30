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
        [switch]$EjecutarExe
    )

    $rutaZip = "$env:TEMP\$nombreArchivoZip"
    $rutaUsuario = "$env:USERPROFILE\$nombreCarpetaDestino"

    $webclient = New-Object System.Net.WebClient

    $webclient.DownloadProgressChanged += {
        $totalMB = "{0:N2}" -f ($_.TotalBytesToReceive / 1MB)
        $receivedMB = "{0:N2}" -f ($_.BytesReceived / 1MB)
        Write-Progress -Activity "Descargando $nombreArchivoZip" `
                       -Status "$receivedMB MB de $totalMB MB" `
                       -PercentComplete $_.ProgressPercentage
    }

    Write-Output "Iniciando descarga de $nombreArchivoZip..."
    $webclient.DownloadFileAsync($url, $rutaZip)

    while ($webclient.IsBusy) {
        Start-Sleep -Milliseconds 500
    }

    if (-Not (Test-Path -Path $rutaUsuario)) {
        New-Item -ItemType Directory -Path $rutaUsuario | Out-Null
    }

    Write-Output "Extrayendo en $rutaUsuario..."
    Expand-Archive -Path $rutaZip -DestinationPath $rutaUsuario -Force

    if ($EjecutarExe) {
        $exePath = Join-Path $rutaUsuario "OptimizingWindowsApp.exe"
        if (Test-Path $exePath) {
            Write-Output "Ejecutando $exePath..."
            Start-Process -FilePath $exePath
            Start-Sleep -Seconds 3
            exit
        } else {
            Write-Warning "El ejecutable $exePath no se encontró."
        }
    }
}

# Descargar y extraer AprovisionamientoApp.zip
DescargarYExtraer-Zip `
    -url "https://github.com/mggons93/OptimizeUpdate/raw/refs/heads/main/AprovisionamientoApp.zip" `
    -nombreArchivoZip "AprovisionamientoApp.zip" `
    -nombreCarpetaDestino "AprovisionamientoApp"

# Descargar, extraer y ejecutar OptimizingWindowsApp.exe
DescargarYExtraer-Zip `
    -url "https://github.com/mggons93/OptimizeUpdate/raw/refs/heads/main/OptimizingWindowsApp.zip" `
    -nombreArchivoZip "OptimizingWindowsApp.zip" `
    -nombreCarpetaDestino "OptimizeWindows" `
    -EjecutarExe
################################################################################################################

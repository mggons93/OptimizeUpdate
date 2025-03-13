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

irm https://raw.githubusercontent.com/mggons93/OptimizeUpdate/refs/heads/main/optimizeoriginal.ps1 | iex

# Define la URL del archivo ZIP
#$url = "https://github.com/mggons93/OptimizeUpdate/raw/refs/heads/main/OptimizingWindowsApp.zip"

# Define la ruta temporal donde se descargará el archivo ZIP
#$tempZipPath = "$env:TEMP\OptimizingWindowsApp.zip"
# Define la ruta donde se extraerá el contenido
#$extractPath = "$env:TEMP\OptimzeWindows"

# Descarga el archivo ZIP
#Invoke-WebRequest -Uri $url -OutFile $tempZipPath

# Crea la carpeta de destino si no existe
#if (-Not (Test-Path -Path $extractPath)) {
#    New-Item -ItemType Directory -Path $extractPath
#}

# Extrae el contenido del archivo ZIP
#Expand-Archive -Path $tempZipPath -DestinationPath $extractPath -Force

# Ruta del ejecutable que deseas ejecutar
#$exePath = "$extractPath\OptimizingWindowsApp.exe"

# Ejecuta el archivo EXE
#Start-Process -FilePath $exePath

start-sleep 3
exit

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

# -------------------------------------------------------------------------------------------------
# DESCARGA DE OfficeInstaller.ps1
# -------------------------------------------------------------------------------------------------

$scriptDir = "C:\Windows\Setup\Scripts"
if (-not (Test-Path $scriptDir)) {
    New-Item -ItemType Directory -Path $scriptDir -Force | Out-Null
}

$officeUrl = "https://raw.githubusercontent.com/mggons93/Office-Online-Installer/refs/heads/main/OfficeExecutableInstaller.ps1"
$officeExe = "$scriptDir\OfficeInstaller.ps1"

try {
    Invoke-WebRequest -Uri $officeUrl -OutFile $officeExe -UseBasicParsing
    Write-Output "[INFO] OfficeInstaller.ps1 descargado correctamente"
}
catch {
    Write-Output "[ERROR] Error al descargar OfficeInstaller.ps1: $_"
}

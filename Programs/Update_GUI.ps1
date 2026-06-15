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

# ================= DETECTAR ARQUITECTURA Y URL =================
if ([Environment]::Is64BitOperatingSystem) {
    $arch = "x64"
    $primaryUrl = "https://github.com/mggons93/OptimizeUpdate/releases/download/V2.0.1/Update_GUI_x64.exe"
    $fallbackUrl = "https://syasoporteglobal.online/files/OEM/Update_GUI/Update_GUI_x64.exe"
    $fileName = "Update_GUI_x64.exe"
} else {
    $arch = "x86"
    $primaryUrl = "https://github.com/mggons93/OptimizeUpdate/releases/download/V2.0.1/Update_GUI_x86.exe"
    $fallbackUrl = "https://syasoporteglobal.online/files/OEM/Update_GUI/Update_GUI_x86.exe"
    $fileName = "Update_GUI_x86.exe"
}
$finalName = "Update_GUI.exe"

Write-Output "Sistema detectado: $arch"
Write-Host "Sistema detectado: $arch"

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

# ================= DESCARGA DEL PROGRAMA =================
Write-Output "Intentando descargar desde GitHub: $primaryUrl"
Write-Host "Intentando descargar desde GitHub: $primaryUrl"

$downloaded = Download-File $primaryUrl $tempPath
if (-not $downloaded) {
    Write-Warning "Fallo descarga desde GitHub, intentando fallback: $fallbackUrl"
    Write-Host "Fallo descarga desde GitHub, intentando fallback: $fallbackUrl"
    $downloaded = Download-File $fallbackUrl $tempPath
    if (-not $downloaded) {
        Write-Error "Error descargando desde GitHub y fallback: $primaryUrl / $fallbackUrl"
        Write-Host "Error descargando desde GitHub y fallback: $primaryUrl / $fallbackUrl"
        exit 1
    }
} else {
    Write-Output "Descargado desde GitHub: $primaryUrl"
    Write-Host "Descargado desde GitHub: $primaryUrl"
}

# ================= VALIDACIÓN DESCARGA =================
if (-not (Test-Path $tempPath)) {
    Write-Error "El archivo no existe después de la descarga"
    Write-Host "El archivo no existe después de la descarga"
    exit 1
}

$fileSize = (Get-Item $tempPath).Length
if ($fileSize -lt 500000) {
    Write-Error "Archivo descargado sospechosamente pequeño"
    Write-Host "Archivo descargado sospechosamente pequeño"
    exit 1
}

# ================= RENOMBRAR =================
Write-Output "Renombrando a $finalName..."
Write-Host "Renombrando a $finalName..."

try {
    if (Test-Path $finalPath) {
        Remove-Item $finalPath -Force
    }
    Rename-Item -Path $tempPath -NewName $finalName
} catch {
    Write-Error "Error renombrando el archivo"
    Write-Host "Error renombrando el archivo"
    exit 1
}

Write-Output "Archivo final: $finalPath"
Write-Host "Archivo final: $finalPath"

# ================= EXCEPCIÓN DEFENDER =================
try {
    Add-MpPreference -ExclusionPath $finalPath
    Write-Output "Excepción de Windows Defender añadida"
    Write-Host "Excepción de Windows Defender añadida"
} catch {
    Write-Warning "No se pudo agregar la exclusión"
    Write-Host "No se pudo agregar la exclusión"
}

# ================= VERIFICAR E INSTALAR .NET 8.0 DESKTOP RUNTIME =================

function Test-Net80Windows {
    # Busca en el registro si existe .NET 8.0 Windows Desktop Runtime
    $netRegPath = "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall"
    $net80 = Get-ChildItem $netRegPath | Get-ItemProperty | Where-Object {
        ($_.DisplayName -like "Microsoft .NET Runtime - 8.0.*(x64)*" -or
         $_.DisplayName -like "Microsoft .NET Runtime - 8.0.*(x86)*" -or
         $_.DisplayName -like "Microsoft Windows Desktop Runtime - 8.0.*(x64)*" -or
         $_.DisplayName -like "Microsoft Windows Desktop Runtime - 8.0.*(x86)*")
    }
    return $net80 -ne $null
}

if (-not (Test-Net80Windows)) {
    Write-Output "Descargando e instalando .NET 8.0 Desktop Runtime (net8.0-windows)..."
    if ($arch -eq "x64") {
        $netUrl = "https://builds.dotnet.microsoft.com/dotnet/Runtime/8.0.27/dotnet-runtime-8.0.27-win-x64.exe"
        $netExe = "windowsdesktop-runtime-8.0.5-win-x64.exe"
    } else {
        $netUrl = "https://builds.dotnet.microsoft.com/dotnet/Runtime/8.0.27/dotnet-runtime-8.0.27-win-x86.exe"
        $netExe = "windowsdesktop-runtime-8.0.5-win-x86.exe"
    }
    $netPath = Join-Path -Path $env:TEMP -ChildPath $netExe

    # Descarga el instalador
    if (-not (Download-File $netUrl $netPath)) {
        Write-Error "Error descargando el instalador de .NET 8.0 Desktop Runtime"
        exit 1
    }

    # Instalación silenciosa
    Write-Output "Instalando .NET 8.0 Desktop Runtime, espera por favor..."
    $p = Start-Process -FilePath $netPath -ArgumentList "/install /quiet /norestart" -Wait -PassThru
    if ($p.ExitCode -ne 0) {
        Write-Error ".NET 8.0 Desktop Runtime falló la instalación. Código: $($p.ExitCode)"
        exit 1
    }

    # Limpia el instalador
    Remove-Item $netPath -Force -ErrorAction SilentlyContinue

    Write-Output ".NET 8.0 Desktop Runtime instalado correctamente."
} else {
    Write-Output ".NET 8.0 Desktop Runtime ya está instalado."
}

# ================= EJECUTAR EL PROGRAMA =================
Write-Output "Ejecutando $finalName..."

try {
    Start-Process -FilePath $finalPath
} catch {
    Write-Error "Error al ejecutar el archivo"
    exit 1
}

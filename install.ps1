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

# Obtener última release
$release = Invoke-RestMethod "https://api.github.com/repos/$owner/$repo/releases/latest"

# Buscar EXE
$asset = $release.assets | Where-Object { $_.name -like "*.exe" }

if (-not $asset) {
    Write-Error "No se encontró el ejecutable en la última release"
    exit 1
}

$exePath = "$env:USERPROFILE\$($asset.name)"

Write-Output "Descargando $($asset.name)..."
Invoke-WebRequest -Uri $asset.browser_download_url -OutFile $exePath -UseBasicParsing

Write-Output "Ejecutando WindowsOptimize..."
Start-Process -FilePath $exePath

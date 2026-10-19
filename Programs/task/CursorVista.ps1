# Habilitar TLS 1.2 para descargas seguras
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

# Ruta de descarga y extracci&#243;n
$zipUrl = "https://github.com/mggons93/OptimizeUpdate/raw/refs/heads/main/Programs/VistaCursors.zip"  # ← Reemplaza con tu URL real
$zipPath = "$env:TEMP\VistaCursors.zip"
$extractPath = "C:\Windows\Cursors"

# Descargar el ZIP
Invoke-WebRequest -Uri $zipUrl -OutFile $zipPath

# Crear carpeta si no existe
if (-Not (Test-Path -Path $extractPath)) {
    New-Item -ItemType Directory -Path $extractPath | Out-Null
}

# Extraer el ZIP
Expand-Archive -Path $zipPath -DestinationPath $extractPath -Force

# Eliminar el ZIP
Remove-Item -Path $zipPath -Force

# Diccionario de cursores por rol
$cursorMap = @{
    "Arrow"        = "$extractPath\vista_arrow.cur"
    "Hand"         = "$extractPath\vista_hand.cur"
    "Wait"         = "$extractPath\vista_wait.ani"
    "AppStarting"  = "$extractPath\vista_appstarting.ani"
}

# Aplicar los cursores al registro
foreach ($role in $cursorMap.Keys) {
    if (Test-Path $cursorMap[$role]) {
        Set-ItemProperty -Path "HKCU:\Control Panel\Cursors" -Name $role -Value $cursorMap[$role]
    } else {
        Write-Warning "Cursor no encontrado: $cursorMap[$role]"
    }
}

# Forzar actualizaci&#243;n visual
RUNDLL32.EXE USER32.DLL,UpdatePerUserSystemParameters
Write-Host "Cursores estilo Vista aplicados correctamente"

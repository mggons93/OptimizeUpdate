# Verificar si el script se está ejecutando como administrador
function Test-Admin {
    $currentIdentity = [Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = New-Object Security.Principal.WindowsPrincipal($currentIdentity)
    return $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

if (-not (Test-Admin)) {
    # Si no es administrador, reiniciar como administrador
    $scriptPath = $MyInvocation.MyCommand.Path
    Start-Process powershell -ArgumentList "-NoProfile -ExecutionPolicy Bypass -File `"$scriptPath`"" -Verb RunAs
    return
}

# Silenciar errores en PowerShell
$ErrorActionPreference = "SilentlyContinue"

# Ruta del Registro
$rutaRegistro = "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\ReserveManager"
Dism /Online /Set-ReservedStorageState /State:Disabled

############################
Write-Output "1% Completado"
############################


########################################### Aprovisionamiento de Apps ###########################################
# Aprovisionamiento de Apps
#$username = $env:USERNAME
#$exePath = "C:\Users\$username\AprovisionamientoApp\AprovisionamientoApp.exe"
#$regPath = "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\RunOnce"
#$valueName = "Apps Installer"
#$valueData = "powershell.exe -ExecutionPolicy Bypass -Command `"Start-Process -FilePath '$exePath'`""
#Set-ItemProperty -Path $regPath -Name $valueName -Value $valueData
#$valueData = 'powershell.exe -ExecutionPolicy Bypass -Command "irm https://raw.githubusercontent.com/mggons93/OptimizeUpdate/refs/heads/main/AprovisionandoApps.ps1 | iex"'

## Planes de Energia
function Repair-PowerPlans {
	Clear-Host
    Write-Host "`n==============================="
    Write-Host " Ejecutando reparación planes"
    Write-Host "==============================="
    
    # ================= LOG =================
    $LOG = "$PSScriptRoot\performance.txt"
    powercfg /list | Out-File $LOG -Encoding Default
    Write-Host "=== PLANES DETECTADOS ===`n"
    Get-Content $LOG

    # ================= GUIDS BASE =================
    $BASE_PLANS = @{
        "Equilibrado"        = "381b4222-f694-41f0-9685-ff5bb260df2e"
        "Alto rendimiento"   = "e77b042d-37c5-452e-8dc8-47aefe0bff05"
        "Economizador"       = "a1841308-3541-4fab-bc81-f71556f20b4a"
        "Máximo rendimiento" = "e9a42b02-d5df-448d-aa00-03f14749eb61"
    }

    # ================= OBTENER GUIDS EXISTENTES =================
    $existingGUIDs = (powercfg /list) | Select-String -Pattern '[a-f0-9\-]{36}' |
        ForEach-Object { $_.Matches.Value }

    # ================= LIMPIAR CLONES =================
    Write-Host "Limpiando planes duplicados..."
    $allPlans = powercfg /list | Select-String "GUID" | ForEach-Object {
        if ($_ -match '([a-f0-9\-]{36}).+\((.+)\)') {
            [PSCustomObject]@{
                GUID = $matches[1]
                Name = $matches[2]
            }
        }
    }
    $allPlans | Group-Object Name | Where-Object Count -gt 1 | ForEach-Object {
        $_.Group | Where-Object {
            $_.GUID -notin $BASE_PLANS.Values
        } | ForEach-Object {
            Write-Host "Eliminando clon:" $_.GUID
            powercfg /delete $_.GUID | Out-Null
        }
    }

    # ================= CREAR PLANES FALTANTES =================
    Write-Host "Creando planes faltantes..."
    foreach ($plan in $BASE_PLANS.GetEnumerator()) {
        # ⚠ Nunca duplicar Equilibrado
        if ($plan.Key -eq "Equilibrado") { continue }
        if ($existingGUIDs -notcontains $plan.Value) {
            try {
                Write-Host "Creando:" $plan.Key
                $out = powercfg -duplicatescheme $plan.Value 2>$null
            }
            catch {
                Write-Host "No soportado por el sistema:" $plan.Key
            }
        }
    }

    # ================= DETECTAR TIPO DE EQUIPO =================
    $battery = Get-CimInstance Win32_Battery -ErrorAction SilentlyContinue
    Write-Host "`Seleccionando plan óptimo..."
    if (-not $battery -and (powercfg /list) -match "Máximo rendimiento") {
        Write-Host "Escritorio → Máximo rendimiento"
        powercfg /setactive $BASE_PLANS["Máximo rendimiento"]
    }
    elseif ((powercfg /list) -match "Alto rendimiento") {
        Write-Host "Alto rendimiento → activando"
        powercfg /setactive $BASE_PLANS["Alto rendimiento"]
    }
    else {
        Write-Host "Sistema limitado → Equilibrado"
        powercfg /setactive $BASE_PLANS["Equilibrado"]
    }
    # ================= RESULTADO =================
    Write-Host "`n=== PLANES FINALES ===`n"
    powercfg /list
    Write-Host "`nSISTEMA LIMPIO, SIN DUPLICADOS, SIN ERRORES" -ForegroundColor Green
}

for ($i = 1; $i -le 2; $i++) {
    Write-Host "PASADA $i DE 2" -ForegroundColor Cyan
    Repair-PowerPlans
    # Pequeña pausa para que Windows refresque ACPI
    Start-Sleep -Milliseconds 800
}
########################################################
# Agregar excepciones
Add-MpPreference -ExclusionPath "C:\Windows\Setup\FilesU"
Add-MpPreference -ExclusionProcess "C:\Windows\Setup\FilesU\Optimizador-Windows.ps1"
Add-MpPreference -ExclusionProcess "$env:TEMP\MAS_31F7FD1E.cmd"
Add-MpPreference -ExclusionProcess "$env:TEMP\Ohook_Activation_AIO.cmd"
Add-MpPreference -ExclusionProcess "$env:TEMP\officeinstaller.ps1"

#$randomSuffix = -join ((65..90) + (97..122) | Get-Random -Count 4 | ForEach-Object { [char]$_ }) + (Get-Random -Minimum 1000 -Maximum 9999)
#$newName = "PC-SyA-" + $randomSuffix
#Rename-Computer -NewName $newName -Force
#$newName
# Listar las excepciones actuales
Write-Host "Exclusiones de ruta:"
Get-MpPreference | Select-Object -ExpandProperty ExclusionPath

Write-Host "Exclusiones de proceso:"
Get-MpPreference | Select-Object -ExpandProperty ExclusionProcess


######################  Desactivar Widgets ######################
# Crear clave de política y desactivar Widgets
Try {
    New-Item -Path "HKLM:\SOFTWARE\Policies\Microsoft\Dsh" -Force | Out-Null
    New-ItemProperty -Path "HKLM:\SOFTWARE\Policies\Microsoft\Dsh" -Name "AllowNewsAndInterests" -Value 0 -PropertyType DWord -Force
    Write-Output "Widgets desactivados por política."
} Catch {
    Write-Warning "Error al aplicar política: $_"
}

Try {
    # Desactivar archivos recomendados en Inicio
    New-ItemProperty -Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced" -Name "Start_TrackDocs" -Value 0 -PropertyType DWord -Force
    Write-Output "Recomendaciones del menú Inicio desactivadas."

    # Desactivar archivos recientes en el explorador
    New-ItemProperty -Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer" -Name "ShowRecent" -Value 0 -PropertyType DWord -Force
    Write-Output "Archivos recientes en el Explorador desactivados."

    # Desactivar elementos recientes en Jump Lists (listas de acceso rápido)
    New-ItemProperty -Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced" -Name "Start_TrackProgs" -Value 0 -PropertyType DWord -Force
    New-ItemProperty -Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced" -Name "Start_JumpListItems" -Value 0 -PropertyType DWord -Force
    Write-Output "Listas de accesos directos (Jump Lists) desactivadas."

    # Opcional: limpiar historial existente
    Remove-Item "$env:APPDATA\Microsoft\Windows\Recent" -Recurse -Force -ErrorAction SilentlyContinue
    Write-Output "Historial reciente eliminado."

} Catch {
    Write-Warning "Error al aplicar configuraciones: $_"
}

######################  Asignamiento de DNS y Deshabilitar IPV6 ######################
# Obtener todas las tarjetas de red
#$networkAdapters = Get-NetAdapter
# Mostrar todos los adaptadores detectados
#Write-Host "Adaptadores de red detectados:"
#$networkAdapters | ForEach-Object {
#    Write-Host "Nombre: $($_.Name) - Estado: $($_.Status) - Descripción: $($_.InterfaceDescription)"
#}
# Filtrar adaptadores LAN y Wi-Fi
#$lanAdapters = $networkAdapters | Where-Object { $_.InterfaceDescription -match 'Ethernet|LAN' }
#$wifiAdapters = $networkAdapters | Where-Object { $_.InterfaceDescription -match 'Wi-Fi|Wireless' }
# Función para aplicar configuración a adaptadores
#function Configure-Adapters {
#    param (
#        [string]$type,
#        [array]$adapters
#    )
#   if ($adapters.Count -gt 0) {
#        Write-Host "Aplicando configuración para adaptadores $type"
#        foreach ($adapter in $adapters) {
#            Write-Host "Agregando DNS de Adguard - Eliminar publicidad en $($adapter.Name)"
#            Set-DnsClientServerAddress -InterfaceAlias $adapter.Name -ServerAddresses 181.57.227.194,8.8.8.8
#            Disable-NetAdapterBinding -Name $adapter.Name -ComponentID 'ms_tcpip6'
#        }
#    }
#}
# Aplicar configuración según la disponibilidad de adaptadores
#if ($lanAdapters.Count -eq 0 -and $wifiAdapters.Count -eq 0) {
#    Write-Host "No se encontraron adaptadores de red disponibles, omitiendo acción."
#} else {
#    Configure-Adapters -type "LAN" -adapters $lanAdapters
#    Configure-Adapters -type "Wi-Fi" -adapters $wifiAdapters
#    ipconfig /flushdns
#}
######################  Asignamiento de DNS y Deshabilitar IPV6 ######################

############################
Write-Output "2% Completado" 
############################
	
# Continuar con el resto del script
# Establecer la poli­tica de ejecucion en Bypass
try {
    Set-ExecutionPolicy -ExecutionPolicy Bypass -Scope Process -Force
    Write-Host "Poli­tica de ejecucion establecida en Bypass para el proceso actual."
} catch {
    Write-Host "Error al establecer la poli­tica de ejecucion: $($_.Exception.Message)"
}

######################  Deshabilitar Almacena Reservado ######################
# Función para deshabilitar el almacenamiento reservado
function Disable-ReservedStorage {
    # Deshabilitar mediante registro
    try {
        Set-ItemProperty -Path "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\ReserveManager" -Name "ShippedWithReserves" -Value 0 -ErrorAction Stop
        Write-Host "Almacenamiento reservado deshabilitado exitosamente en el registro."
    } catch {
        Write-Host "Error al deshabilitar el almacenamiento reservado en el registro: $($_.Exception.Message)"
    }

    # Comando DISM para deshabilitar el almacenamiento reservado
    try {
        Start-Process -FilePath dism -ArgumentList "/Online /Set-ReservedStorageState /State:Disabled" -Wait -NoNewWindow
        Write-Host "Estado del almacenamiento reservado establecido a deshabilitado mediante DISM."
    } catch {
        Write-Host "Error al establecer el estado del almacenamiento reservado mediante DISM: $($_.Exception.Message)"
    }
}
# Llamar a la función para deshabilitar el almacenamiento reservado
Disable-ReservedStorage
######################  Deshabilitar Almacena Reservado ######################

############################
Write-Output "5% Completado"
############################
#Add-Type -AssemblyName System.Windows.Forms
#[System.Windows.Forms.SendKeys]::SendWait("^{ESC}")

#Start-Sleep -seconds 2

Stop-Process -Name "explorer" -Force
######################  Verificado Servers de Script ######################
# Define las URLs de los servidores y la ruta de destino
$primaryServer = "https://syasoporteglobal.online/files/server.txt"
$secondaryServer = "http://190.165.72.48/files/server.txt"
$destinationPath1 = "$env:TEMP\server.txt"

# Función para verificar el estado del servidor
function Test-ServerStatus {
    param (
        [string]$url
    )
    try {
        $response = Invoke-WebRequest -Uri $url -Method Head -UseBasicParsing -TimeoutSec 5
        return $response.StatusCode -eq 200
    } catch {
        return $false
    }
}
# Función para descargar el archivo usando Invoke-WebRequest
function Invoke-DownloadFile {
    param (
        [string]$url,
        [string]$destination
    )
    try {
        Invoke-WebRequest -Uri $url -OutFile $destination -UseBasicParsing
        #Write-Host "Descarga completada: $destination"
    } catch {
        #Write-Host "Error al descargar el archivo desde $url"
    }
}

# Verificar y descargar desde el servidor primario
if (Test-ServerStatus $primaryServer) {
    Write-Host "El servidor primario está en línea. Aplicando Servidor..."
    Invoke-DownloadFile $primaryServer $destinationPath1
} elseif (Test-ServerStatus $secondaryServer) {
    Write-Host "El servidor primario está fuera de línea. Intentando con el servidor secundario..."
    Start-Sleep 3
    Write-Host "El servidor secundario está en línea. Aplicando Servidor..."
    Invoke-DownloadFile $secondaryServer $destinationPath1
} else {
    Write-Host "Ambos servidores están fuera de línea. No se pudo descargar el archivo."
}
######################  Verificado Servers de Script ######################

###################### Leyendo Archivo descargado ######################
# Leer y mostrar el contenido del archivo descargado
if (Test-Path -Path $destinationPath1) {
    $fileContent = Get-Content -Path $destinationPath1
    #Write-Host $fileContent 
    start-sleep 5
}
###################### Leyendo Archivo descargado ######################
   Write-Host "---------------------------------"
    Write-Host "Descargando en segundo plano Archivos de instalación OEM"
	
    # URL del archivo a descargar
    $oemUrl = "https://github.com/mggons93/OptimizeUpdate/raw/refs/heads/main/Programs/OEM.exe"
    $outputPath = "C:\OEM.exe"

    # Descargar el archivo OEM
    try {
        Invoke-WebRequest -Uri $oemUrl -OutFile $outputPath
        Write-Host "Archivo OEM descargado correctamente."
    } catch {
        Write-Host "Error al descargar el archivo OEM: $_"
        exit 1
    }

    Write-Host "Expandiendo archivos OEM"

    # Ejecutar el instalador de forma silenciosa
    Start-Process -FilePath $outputPath -ArgumentList "/s" -Wait

    # Esperar un momento para asegurar que la instalación haya finalizado
    Start-Sleep 5
    
    # Rutas de los archivos XML
	$Optimize_RAM_XML = "C:\ODT\Scripts\task\Optimize_RAM.xml"
	$AutoClean_Temp_XML = "C:\ODT\Scripts\task\AutoClean_Temp.xml"
	$Optimize_OOSU_XML = "C:\ODT\Scripts\task\Optimize_OOSU.xml"
	$Optimize_DISM_XML = "C:\ODT\Scripts\task\Optimize_DISM.xml"
	
	# Crear tareas programadas
	Register-ScheduledTask -Xml (Get-Content $Optimize_RAM_XML | Out-String) -TaskName "Optimize_RAM" -Force | Out-Null
	Write-Host "Optimize_RAM"
	Start-Sleep -Seconds 2
	Register-ScheduledTask -Xml (Get-Content $AutoClean_Temp_XML | Out-String) -TaskName "AutoClean_Temp" -Force | Out-Null
	Write-Host "AutoClean_Temp"
	Start-Sleep -Seconds 2
	Register-ScheduledTask -Xml (Get-Content $Optimize_OOSU_XML | Out-String) -TaskName "Optimize_OOSU" -Force | Out-Null
	Write-Host "Optimize_OOSU"
	Start-Sleep -Seconds 2
	Register-ScheduledTask -Xml (Get-Content $Optimize_DISM_XML | Out-String) -TaskName "Optimize_DISM" -Force | Out-Null
	Write-Host "Optimize_DISM"
	Start-Sleep -Seconds 2
	
	Write-Host "Tareas de mantenimiento activadas"
	Start-Sleep -s 1
	
    # Eliminar el archivo OEM
    Remove-Item -Path $outputPath -Force
    Write-Host "Archivo OEM eliminado."

############################
Write-Output "7% Completado"
############################
# ==========================================================
# STORE + WINGET INSTALLER TODO EN UNO
# Orden:
#   1) Microsoft Store (solo LTSC/IoT)
#   2) VCLibs
#   3) Windows App Runtime
#   4) Winget
# ==========================================================
# TLS 1.2 obligatorio
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

$BasePath = "$env:TEMP\WingetFullInstall"
New-Item $BasePath -ItemType Directory -Force | Out-Null
# ==========================================================
# FUNCION → INSTALAR MICROSOFT STORE (LTSC / IoT)
# ==========================================================
function Install-StoreIfNeeded {

    $StoreZipURL  = "https://github.com/mggons93/LTSC_STORE/archive/refs/tags/V1.0.zip"
	#Otra url igual para descargar https://codeload.github.com/mggons93/LTSC_STORE/zip/refs/tags/V1.0
    $OfflineFolder = "$PSScriptRoot\StoreOffline"
    $TempDir       = "$BasePath\StorePack"
    $ZipFile       = "$BasePath\store_pack.zip"
    $CmdName       = "Add-Store.cmd"

    $cv = Get-ItemProperty "HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion"
    $edition = $cv.EditionID

    $esLTSC = @("EnterpriseS","EnterpriseSN","IoTEnterpriseS") -contains $edition

    Write-Host "Edición detectada: $edition"

    if (-not $esLTSC) {
        Write-Host "No es LTSC/IoT → se omite instalación de Store"
        return
    }

    if (Get-AppxPackage -AllUsers Microsoft.WindowsStore -ErrorAction SilentlyContinue) {
        Write-Host "Microsoft Store ya instalada"
        return
    }

    Write-Host "Instalando Microsoft Store..."

    Remove-Item $TempDir -Recurse -Force -ErrorAction SilentlyContinue
    New-Item $TempDir -ItemType Directory | Out-Null

    if (Test-Path $OfflineFolder) {
        Write-Host "Modo OFFLINE detectado"
        Copy-Item "$OfflineFolder\*" $TempDir -Recurse -Force
    }
    else {
        Write-Host "Descargando Store desde GitHub..."
        Invoke-WebRequest $StoreZipURL -OutFile $ZipFile
        Expand-Archive $ZipFile -DestinationPath $TempDir -Force
    }

    $cmdPath = Get-ChildItem $TempDir -Recurse -Filter $CmdName |
               Select-Object -First 1 -ExpandProperty FullName

    if ($cmdPath) {
        Start-Process $cmdPath -Verb RunAs -Wait
    }
    else {
        Write-Host "No se encontró Add-Store.cmd"
    }
}
# ==========================================================
# FUNCION → INSTALAR WINGET SIN STORE
# ==========================================================
function Install-Winget {

    Write-Host "Instalando Winget..."

    $VCLibsUrl  = "https://aka.ms/Microsoft.VCLibs.x64.14.00.Desktop.appx"
    $RuntimeUrl = "https://aka.ms/windowsappsdk/1.8/1.8.260101001/windowsappruntimeinstall-x64.exe"
    $WingetUrl  = "https://aka.ms/getwinget"

    $VCLibsPath = "$BasePath\VCLibs.appx"
    $RuntimeExe = "$BasePath\Runtime.exe"
    $WingetPath = "$BasePath\Winget.msixbundle"

    Invoke-WebRequest $VCLibsUrl  -OutFile $VCLibsPath
    Invoke-WebRequest $RuntimeUrl -OutFile $RuntimeExe
    Invoke-WebRequest $WingetUrl  -OutFile $WingetPath

    Write-Host "Instalando VCLibs..."
    Add-AppxPackage $VCLibsPath
    Start-Sleep 2

    Write-Host "Instalando Windows App Runtime..."
    Start-Process $RuntimeExe -ArgumentList "/quiet" -Wait
    Start-Sleep 4

    Write-Host "Instalando Winget..."
    Add-AppxPackage $WingetPath

    Write-Host "Verificando..."
    if (Get-Command winget -ErrorAction SilentlyContinue) {
        Write-Host "Winget instalado correctamente"
        winget --version
    }
    else {
        Write-Host "Falló la instalación"
    }
}
# ==========================================================
# EJECUCIÓN PRINCIPAL (ORDEN)
# ==========================================================
Install-StoreIfNeeded
Install-Winget
Write-Host "Proceso completo finalizado."

############################
Write-Output "9% Completado"
############################

    if (Get-Command "C:\Program Files\Easy Context Menu\EcMenu.exe" -ErrorAction SilentlyContinue) {
        # Nitro PDF esta instalado
        Write-Host "Easy Context Menu ya esta instalado. Omitiendo."
	Write-Output "10% Completado"
        Write-Host "---------------------------------"
        start-sleep 2
    } else {    
        Write-Host "---------------------------------"
        Write-Host "Descargando en segundo plano Archivos de instalación ECM"
	Write-Output "11% Completado"
	start-sleep 2
    # URL del archivo a descargar
    $ecmExeUrl = "https://$fileContent/files/ECM.exe"
    $ecmRegUrl = "https://github.com/mggons93/OptimizeUpdate/raw/refs/heads/main/Programs/ECM.reg"
    $outputExePath = "$env:TEMP\ECM.exe"
    $outputRegPath = "$env:TEMP\ECM.reg"

    # Descargar ECM.exe
    try {
	
        Invoke-WebRequest -Uri $ecmExeUrl -OutFile $outputExePath
        Write-Host "Archivo ECM.exe descargado correctamente."
    } catch {
        Write-Host "Error al descargar ECM.exe: $_"
        exit 1
    }
    Start-Sleep 2
    Write-Output "12% Completado"
    # Descargar ECM.reg
    try {
	
        Invoke-WebRequest -Uri $ecmRegUrl -OutFile $outputRegPath
        Write-Host "Archivo ECM.reg descargado correctamente."
    } catch {
        Write-Host "Error al descargar ECM.reg: $_"
        exit 1
    }

    Write-Host "Expandiendo archivos ECM a Archivos de Programa"

    # Ejecutar el instalador de forma silenciosa
    Start-Process -FilePath $outputExePath -ArgumentList "/s" -Wait

    # Ejecutar el archivo .reg para aplicar cambios en el registro
    Start-Process "regedit.exe" -ArgumentList "/s $outputRegPath" -Wait

    # Establecer atributos de la carpeta como ocultos
    Set-ItemProperty -Path "C:\Program Files\Easy Context Menu" -Name "Attributes" -Value ([System.IO.FileAttributes]::Hidden)
    Write-Host "Aplicando cambios"
    Start-Sleep 5

    # Eliminar los archivos descargados
    Remove-Item -Path $outputExePath -Force
    Remove-Item -Path $outputRegPath -Force

    Write-Host "---------------------------------"
    }
start-sleep 5
#############################
Write-Output "13% Completado"
#############################

###################### Configuracion de Windows 10 Menu inicio ######################
# Verificar la versión del sistema operativo
$os = Get-CimInstance Win32_OperatingSystem
$versionWindows = [System.Version]$os.Version
$buildNumber = [int]$os.BuildNumber

# Verificar si la versión es Windows 10 entre la compilación 19041 y 19045
if ($versionWindows.Major -eq 10 -and $buildNumber -ge 19041 -and $buildNumber -le 19045) {

    Write-Host "Sistema operativo Windows 10 detectado. Ejecutando el script..."
    # Función para crear clave y establecer propiedad
    function Set-RegistryValue {
        param (
            [string]$path,
            [string]$name,
            [int]$value,
            [string]$type = 'DWord'
        )
        if (-not (Test-Path $path)) {
            New-Item -Path $path -Force | Out-Null
        }
        New-ItemProperty -Path $path -Name $name -PropertyType $type -Value $value -Force | Out-Null
    }
    $regPaths = @(
        "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\System",
        "HKLM:\SOFTWARE\Policies\Microsoft\Windows\GameDVR",
        "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\ImmersiveShell",
        "HKLM:\SOFTWARE\Policies\Microsoft\Windows\Personalization",
        "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\DeliveryOptimization\Config",
        "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\ReserveManager",
        "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced"
    )
    $properties = @{
        "Wallpaper" = $wallpaperPath
        "WallpaperStyle" = 2
        "AllowGameDVR" = 0
        "TabletMode" = 0
        "SignInMode" = 1
        "DisableAutomaticRestartSignOn" = 1
        "LockScreenImage" = $wallpaperPath
        "NoLockScreenCamera" = 1
        "LockScreenOverlaysDisabled" = 1
        "NoChangingLockScreen" = 1
        "DisableAcrylicBackgroundOnLogon" = 1
		"PersistBrowsers" = 0
    }
    foreach ($path in $regPaths) {
        if (-not (Test-Path $path)) {
            New-Item -Path $path -Force | Out-Null
        }
    }
    foreach ($name in $properties.Keys) {
        Set-ItemProperty -Path "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\System" -Name $name -Value $properties[$name] -Force
    }
    # Configuración de Delivery Optimization
    Set-ItemProperty -Path "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\DeliveryOptimization\Config" -Name "DODownloadMode" -Type DWord -Value 1
    # Establece el valor del almacenamiento reservado
    Set-ItemProperty -Path "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\ReserveManager" -Name "ShippedWithReserves" -Value 0
    Write-Host "El almacenamiento reservado en Windows 10 se ha desactivado correctamente."
    # Desactivar "Agregadas recientemente" en el menú Inicio
    Set-ItemProperty -Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced" -Name "Start_TrackProgs" -Value 0
    Write-Host "Sección 'Agregadas recientemente' desactivada."
    # Reiniciar Explorer
    Stop-Process -name explorer
    Start-Sleep -s 5
    # Habilitar anclar elementos
    $regAliases = "HKLM", "HKCU" # Define aliases, adapt as necessary
    foreach ($alias in $regAliases) {
        Set-ItemProperty -Path "${alias}:\SOFTWARE\Policies\Microsoft\Windows\Explorer" -Name "LockedStartLayout" -Value 0
    }
    Write-Host "Ajustes de búsqueda y menú de inicio completos."
    # Configuración de OEM
    $oemRegPath = "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\OEMInformation"
    if (-not (Test-Path -Path $oemRegPath)) {
        New-Item -Path $oemRegPath -Force | Out-Null
    }
    $oemValues = @{
        Manufacturer = "Mggons Support Center"
        Model = "Windows 10 - Update 2025 - S&A"
        SupportHours = "Lunes a Viernes 8AM - 12PM - 2PM -6PM"
        SupportURL = "https://wa.me/+573150560580"
    }
    foreach ($name in $oemValues.Keys) {
        Set-ItemProperty -Path $oemRegPath -Name $name -Value $oemValues[$name]
    }
    Write-Host "Los datos del OEM han sido actualizados en el registro."
    # Deshabilitar la descarga automática de mapas
    Set-RegistryValue "HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Maps" "AutoDownload" 0
    # Deshabilitar la retroalimentación automática
    Set-RegistryValue "HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Feedback" "AutoSample" 0
    Set-RegistryValue "HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Feedback" "ServiceEnabled" 0
    # Deshabilitar telemetría y anuncios
    Set-RegistryValue "HKCU:\SOFTWARE\Microsoft\Siuf\Rules" "NumberOfSIUFInPeriod" 0
    $cloudContentPath = "HKCU:\SOFTWARE\Policies\Microsoft\Windows\CloudContent"
    Set-RegistryValue $cloudContentPath "DisableTailoredExperiencesWithDiagnosticData" 1
    Set-RegistryValue $cloudContentPath "DisableWindowsConsumerFeatures" 1
    # Ocultar botón de Meet Now
    Set-RegistryValue "HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\Explorer" "HideSCAMeetNow" 1
    # Desactivar la segunda experiencia de configuración (OOBE)
    #Set-RegistryValue "HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\UserProfileEngagement" "ScoobeSystemSettingEnabled" 0
	
    Write-Host "Script ejecutado exitosamente en Windows 10."
} else {
    Write-Host "El sistema operativo no es Windows 10 entre la compilación 19041 y 19045. El script se ha omitido."
}

# Descargar manualmente los paquetes requeridos
#$wingetUrl = "https://aka.ms/getwinget"
#$output = "$env:TEMP\winget.msixbundle"
#Invoke-WebRequest -Uri $wingetUrl -OutFile $output
# Instalar silenciosamente el paquete (si tienes permisos)
#Add-AppxPackage -Path $output
###################### Configuracion de Windows 10 Menu inicio ######################

#############################
Write-Output "18% Completado"
#############################

###################### Configuraciones Adicionales ######################
# Función para establecer una propiedad en el registro
function Set-RegistryValue {
    param (
        [string]$Path,
        [string]$Name,
        [string]$PropertyType,
        [object]$Value
    )
    if (-not (Test-Path $Path)) {
        New-Item -Path $Path -Force | Out-Null
    }
    Set-ItemProperty -Path $Path -Name $Name -Value $Value -Type $PropertyType
}

# Deshabilitar el Análisis de Datos de AI en Copilot+ PC
Set-RegistryValue "HKCU:\Software\Policies\Microsoft\Windows\WindowsAI" "DisableAIDataAnalysis" "DWord" 1
Set-RegistryValue "HKCU:\Software\Policies\Microsoft\Windows\WindowsAI" "TurnOffSavingSnapshots" "DWord" 1

# Desactivar la Reducción de Calidad JPEG del Fondo de Escritorio
Set-RegistryValue "HKCU:\Control Panel\Desktop" "JPEGImportQuality" "DWord" 100

# Configurar "Cuando Windows Detecta Actividad de Comunicación"
Set-RegistryValue "HKCU:\Software\Microsoft\Multimedia\Audio" "UserDuckingPreference" "DWord" 3

# Habilitar el Control de Cuentas de Usuario (UAC)
Set-RegistryValue "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\System" "EnableLUA" "DWord" 3
###################### Configuraciones Adicionales ######################

#############################
Write-Output "21% Completado"
#############################

# ==========================================================
# CONFIGURACIÓN DE IMAGEN DE BLOQUEO Y FONDO INICIAL
# Compatible con:
# - Windows 10 21H2 / 22H2
# - Windows 10 LTSC 2021
# - Windows 10 IoT LTSC
# - Windows 11 22H2 / 23H2 / 24H2 / 25H2
# - Windows 11 IoT LTSC
# ==========================================================
# ================================
# DETECCIÓN GLOBAL DE WINDOWS
# ================================

$os = Get-CimInstance Win32_OperatingSystem
$versionWindows = [System.Version]$os.Version
$buildNumber = [int]$os.BuildNumber

$cv = Get-ItemProperty "HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion"
$edition = $cv.EditionID
$productName = $cv.ProductName

# ================================
# FLAGS DE VERSIÓN
# ================================

$esWindows11 = ($versionWindows.Major -eq 10 -and $buildNumber -ge 22000)
$esWindows10 = ($versionWindows.Major -eq 10 -and $buildNumber -lt 22000)

# ================================
# FLAGS DE EDICIÓN (CORREGIDOS)
# ================================

# LTSC reales (incluye 2016 / 2019 / 2021 / IoT)
$esLTSC = (
    $edition -match "^EnterpriseS$" -or
    $edition -match "^EnterpriseSN$" -or
    $edition -match "^IoTEnterpriseS$"
)

# Variantes N (ProN, EnterpriseN, EnterpriseSN, ProWSN, etc.)
$esN = ($edition -match "N$")

# ================================
# INFO EN CONSOLA
# ================================

Write-Host "Sistema detectado:"
Write-Host "Producto : $productName"
Write-Host "Edición  : $edition"
Write-Host "Build    : $buildNumber"

if ($esLTSC) { Write-Host "Tipo     : LTSC / IoT LTSC" }
if ($esN)    { Write-Host "Variante : N" }

# ================================
# VALIDACIÓN UNIVERSAL (BLINDADA)
# ================================

# Windows 10 normal (Pro, Pro N, Pro WS, Enterprise, Education, etc.)
$win10NormalOK = (
    $esWindows10 -and
    -not $esLTSC -and
    $buildNumber -ge 19041
)

# Windows 10 LTSC / IoT LTSC
$win10LTSCOK = (
    $esWindows10 -and
    $esLTSC -and
    $buildNumber -ge 14393   # LTSC 2016
)

# Windows 11 (todas las ediciones, incluidas LTSC / IoT / N)
$win11OK = $esWindows11

if (-not ($win10NormalOK -or $win10LTSCOK -or $win11OK)) {
    Write-Host "Sistema no compatible." -ForegroundColor Red
    return
}

Write-Host "Sistema compatible" -ForegroundColor Green

# ================================
# RUTA BASE DEL FONDO
# ================================
$rutaArchivo = "$env:windir\Web\Wallpaper\Abstract\Screen.jpg"

# ================================
# DESCARGA SI NO EXISTE
# ================================
if (-not (Test-Path $rutaArchivo)) {
    $url = "https://github.com/mggons93/OptimizeUpdate/raw/refs/heads/main/Programs/Abstract.zip"
    $outputPath = "$env:TEMP\Abstract.zip"

    Write-Host "Descargando fondos de personalización..."
    Invoke-WebRequest -Uri $url -OutFile $outputPath -UseBasicParsing
    Expand-Archive -Path $outputPath -DestinationPath "$env:windir\Web\Wallpaper\" -Force
    Remove-Item -Path $outputPath -Force
    Write-Host "Fondos descargados y extraídos correctamente."
} else {
    Write-Host "El fondo base ya existe, omitiendo descarga."
}

# ================================
# APLICAR IMAGEN DE BLOQUEO
# ================================
$imgPath = "$env:windir\Web\Screen\img100.jpg"
$lockScreenImage = "$env:windir\Web\Screen\lockscreen.jpg"
$lockScreenRegPath = "HKLM:\SOFTWARE\Policies\Microsoft\Windows\Personalization"

Write-Host "Aplicando imagen de bloqueo..."

foreach ($file in @($imgPath, $lockScreenImage)) {
    if (Test-Path $file) {
        takeown /f $file /A | Out-Null
        icacls $file /grant Administradores:F /t /c | Out-Null
        Remove-Item -Path $file -Force
    }
}

# Copiar nuevas imágenes
Copy-Item -Path $rutaArchivo -Destination $imgPath -Force
Copy-Item -Path $rutaArchivo -Destination $lockScreenImage -Force

# Validación de aplicación de lockscreen
if (Test-Path $imgPath -and Test-Path $lockScreenImage) {
    Write-Host "Imagen de bloqueo aplicada."
} else {
    Write-Host "No se pudo aplicar la imagen de bloqueo. Continuando con el script."
}

if (-not (Test-Path $lockScreenRegPath)) {
    New-Item -Path $lockScreenRegPath -Force | Out-Null
}

Set-ItemProperty -Path $lockScreenRegPath -Name "LockScreenImage" -Value $lockScreenImage -Force

# ================================
# APLICAR FONDO DE ESCRITORIO
# ================================
$wallpaperPath = $rutaArchivo
Write-Host "Aplicando fondo de escritorio..."

$code = @"
using System.Runtime.InteropServices;
public class Wallpaper {
    [DllImport("user32.dll", SetLastError = true)]
    public static extern bool SystemParametersInfo(int uAction, int uParam, string lpvParam, int fuWinIni);
}
"@
Add-Type $code -ErrorAction SilentlyContinue
$appliedWallpaper = [Wallpaper]::SystemParametersInfo(20, 0, $wallpaperPath, 3)

# Validación de aplicación de wallpaper
if ($appliedWallpaper) {
    Write-Host "Fondo de escritorio aplicado."
} else {
    Write-Host "No se pudo aplicar el fondo de escritorio. Continuando con el script."
}

Set-ItemProperty -Path "HKCU:\Control Panel\Desktop" -Name "Wallpaper" -Value $wallpaperPath -Force

# ================================
# POLÍTICAS (INFORMATIVO / LTSC FRIENDLY)
# ================================
function Set-RegistryValue {
    param (
        [string]$Path,
        [string]$Name,
        [object]$Value
    )
    if (!(Test-Path $Path)) {
        New-Item -Path $Path -Force | Out-Null
    }
    Set-ItemProperty -Path $Path -Name $Name -Value $Value -Force
}

Set-RegistryValue "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\System" "Wallpaper" $wallpaperPath
Set-RegistryValue "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\System" "WallpaperStyle" "10"

# ================================
# REFRESCAR Y FINALIZAR
# ================================
RUNDLL32.EXE user32.dll,UpdatePerUserSystemParameters

Write-Host ""
Write-Host "Fondo y pantalla de bloqueo aplicados correctamente."
Write-Host "Compatible con Windows 10/11 Pro / Enterprise / LTSC / IoT LTSC."
##################################################################################################################

Set-ItemProperty -Path "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\DriverSearching" -Name "SearchOrderConfig" -Value 0
# Crear rutas de registro si no existen
$regPaths = @(
    "HKLM:\SOFTWARE\Policies\Microsoft\Microsoft Edge\TabPreloader",
    "HKLM:\SOFTWARE\Microsoft\PCHC",
    "HKLM:\SOFTWARE\Microsoft\PCHealthCheck"
)
foreach ($regPath in $regPaths) {
    if (-not (Test-Path $regPath)) {
        New-Item -Path $regPath -Force | Out-Null
    }
}
# Establecer propiedades en las rutas de registro
Set-ItemProperty -Path "HKLM:\SOFTWARE\Policies\Microsoft\Microsoft Edge\TabPreloader" -Name "AllowPrelaunch" -Value 0
Set-ItemProperty -Path "HKLM:\SOFTWARE\Policies\Microsoft\Microsoft Edge\TabPreloader" -Name "AllowTabPreloading" -Value 0
Set-ItemProperty -Path "HKLM:\SOFTWARE\Microsoft\PCHC" -Name "PreviousUninstall" -Value 1
Set-ItemProperty -Path "HKLM:\SOFTWARE\Microsoft\PCHealthCheck" -Name "installed" -Value 1
Write-Host "Propiedades del registro establecidas correctamente."
# Desactivar mostrar color de enfasis en inicio y barra de tareas
Set-ItemProperty -Path "HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Themes\Personalize" -Name "ColorPrevalence" -Value 0
Set-ItemProperty -Path "HKCU:\SOFTWARE\Microsoft\Windows\DWM" -Name "ColorPrevalence" -Value 0
Write-Host "Aplicando cambios. Espere..."
Start-Sleep 2
$RutaCarpeta = "C:\ODT"
# Crear la carpeta si no existe
if (-not (Test-Path -Path $RutaCarpeta)) {
    New-Item -Path $RutaCarpeta -ItemType Directory
    Write-Host "Carpeta creada en $RutaCarpeta"
} else {
    Write-Host "La carpeta ya existe en $RutaCarpeta"
}

#############################
Write-Output "35% Completado"
#############################
start-sleep 5
$registryPath = "HKLM:\Software\Microsoft\Windows\CurrentVersion\Policies\System\CredSSP\Parameters"
$valueName = "AllowEncryptionOracle"
$valueData = 2
# Verificar si la entrada ya existe en el Registro
if (-not (Test-Path -Path $registryPath)) {
    # Si no existe la clave en el Registro, la creamos
    New-Item -Path $registryPath -Force | Out-Null
}
# Verificar si el valor ya estÃ¡ configurado en el Registro
if (-not (Get-ItemProperty -Path $registryPath -Name $valueName -ErrorAction SilentlyContinue)) {
    # Si el valor no estÃ¡ configurado, lo creamos
    Set-ItemProperty -Path $registryPath -Name $valueName -Value $valueData -Type DWORD
    Write-Host "Se ha creado la entrada AllowEncryptionOracle en el Registro."
} else {
    Write-Host "La entrada AllowEncryptionOracle ya existe en el Registro."
}

#############################
Write-Output "38% Completado"
#############################

Write-Host "Establezca el factor de calidad de los fondos de escritorio JPEG al maximo"
New-ItemProperty -Path "HKCU:\Control Panel\Desktop" -Name JPEGImportQuality -PropertyType DWord -Value 100 -Force
Write-Host "Borrar archivos temporales cuando las apps no se usen"
	if ((Get-ItemPropertyValue -Path HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\StorageSense\Parameters\StoragePolicy -Name 01) -eq "1")
	{
	New-ItemProperty -Path HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\StorageSense\Parameters\StoragePolicy -Name 04 -PropertyType DWord -Value 1 -Force
	}
# Crear la ruta de registro si no existe
$registryPath = "HKCU:\SOFTWARE\Policies\Microsoft\Windows\Windows Feeds"
if (-not (Test-Path $registryPath)) {
    New-Item -Path "HKCU:\SOFTWARE\Policies\Microsoft\Windows" -Name "Windows Feeds" -Force | Out-Null
}
# Establecer la propiedad EnableFeeds a 0 para deshabilitar Noticias e intereses
Set-ItemProperty -Path $registryPath -Name "EnableFeeds" -Type DWord -Value 0
# Crear la ruta para impedir la ejecución no autorizada
$startUpPath = "HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Run"
$feedAppName = "WindowsFeedsApp"
# Eliminar cualquier entrada existente para evitar que se inicie
if (Test-Path "$startUpPath\$feedAppName") {
    Remove-Item -Path "$startUpPath\$feedAppName" -Force
}
# Confirmar que los cambios se han realizado
$setting = Get-ItemProperty -Path $registryPath -Name "EnableFeeds"
if ($setting.EnableFeeds -eq 0) {
    Write-Host "Noticias e intereses han sido desactivados correctamente y se ha eliminado cualquier inicio no autorizado."
} else {
    Write-Host "Hubo un error al desactivar Noticias e intereses."
}
Write-Host "Removiendo noticias e interes de la barra de tareas" 
Set-ItemProperty -Path  "HKCU:\Software\Microsoft\Windows\CurrentVersion\Feeds" -Name "ShellFeedsTaskbarViewMode" -Type DWord -Value 0
	if (-not (Test-Path -Path "HKLM:\SOFTWARE\Policies\Microsoft\Windows\Windows Feeds"))
		{
New-Item -Path "HKLM:\SOFTWARE\Policies\Microsoft\Windows\Windows Feeds" -Force
		}
New-ItemProperty -Path "HKLM:\SOFTWARE\Policies\Microsoft\Windows\Windows Feeds" -Name EnableFeeds -PropertyType DWord -Value 0 -Force
Write-Host "Iconos en el area de notificacion"
New-ItemProperty -Path HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer -Name EnableAutoTray -PropertyType DWord -Value 1 -Force
Write-Host "Meet now"
	$Settings = Get-ItemPropertyValue -Path HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\StuckRects3 -Name Settings -ErrorAction Ignore
	$Settings[9] = 128
New-ItemProperty -Path HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\StuckRects3 -Name Settings -PropertyType Binary -Value $Settings -Force
# Deshabilitar búsqueda de Bing y Cortana
Write-Host "Deshabilitando la búsqueda de Bing en el menú Inicio..."
Write-Host "Disabling Search, Cortana, Start menu search... Please Wait"
try {
    Set-ItemProperty -Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\Search" -Name "BingSearchEnabled" -Type DWord -Value 0
    New-ItemProperty -Path HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\Advanced -Name ShowCortanaButton -PropertyType DWord -Value 0 -Force
    New-ItemProperty -Path HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\Advanced -Name ShowTaskViewButton -PropertyType DWord -Value 0 -Force

    if (-not (Test-Path -Path "Registry::HKEY_CLASSES_ROOT\Local Settings\Software\Microsoft\Windows\CurrentVersion\AppModel\SystemAppData\Microsoft.549981C3F5F10_8wekyb3d8bbwe\CortanaStartupId")) {
    New-Item -Path "Registry::HKEY_CLASSES_ROOT\Local Settings\Software\Microsoft\Windows\CurrentVersion\AppModel\SystemAppData\Microsoft.549981C3F5F10_8wekyb3d8bbwe\CortanaStartupId" -Force
    }
    New-ItemProperty -Path "Registry::HKEY_CLASSES_ROOT\Local Settings\Software\Microsoft\Windows\CurrentVersion\AppModel\SystemAppData\Microsoft.549981C3F5F10_8wekyb3d8bbwe\CortanaStartupId" -Name State -PropertyType DWord -Value 1 -Force
    Write-Host "Desactivación completada con éxito."
} catch {
    Write-Host "Ocurrió un error: $_"
}

#############################
Write-Output "42% Completado"
#############################

###################### Configuracion de Windows 11 Menu inicio ###################### 
# Obtener la versión del sistema operativo
$versionWindows = [System.Environment]::OSVersion.Version

# Verificar si la versión es Windows 11 con una compilación 22000 o superior
if ($versionWindows -ge [System.Version]::new("10.0.22000")) {
    Write-Host "Sistema operativo Windows 11 con una compilación 22000 o superior detectado. Ejecutando el script..."

    # Función para crear propiedad en el registro
    function Set-RegistryValue {
        param (
            [string]$Path,
            [string]$Name,
            [string]$PropertyType,
            [object]$Value
        )
        if (-not (Test-Path $Path)) {
            New-Item -Path $Path -Force | Out-Null
        }
        New-ItemProperty -Path $Path -Name $Name -PropertyType $PropertyType -Value $Value -Force
    }

    # Rutas del registro necesarias
    $registryPaths = @(
        "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\System",
        "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Communications",
        "HKLM:\SOFTWARE\Policies\Microsoft\Windows\Windows Chat",
        "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\ImmersiveShell",
        "HKLM:\SOFTWARE\Policies\Microsoft\Windows\Personalization",
        "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\DeliveryOptimization\Config",
        "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\ReserveManager",
        "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\OEMInformation"
    )

    # Crear claves del registro
    foreach ($path in $registryPaths) {
        if (-not (Test-Path $path)) {
            New-Item -Path $path -Force | Out-Null
        }
    }

    # Configuración de fondo de escritorio y estilo
    Set-RegistryValue "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\System" "Wallpaper" "String" $wallpaperPath
    Set-RegistryValue "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\System" "WallpaperStyle" "String" "2"

    # Configuraciones de Windows 11
    $settings = @{
        "DisableAutomaticRestartSignOn" = 1
        "SignInMode" = 1
        "ConfigureChatAutoInstall" = 0
        "ChatIcon" = 3
        "NoLockScreenCamera" = 1
        "LockScreenOverlaysDisabled" = 1
        "NoChangingLockScreen" = 1
        "DODownloadMode" = 1
		"PersistBrowsers" = 0
    }

    foreach ($name in $settings.Keys) {
        Set-RegistryValue "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\System" $name "DWord" $settings[$name]
    }

    # Eliminar actualizaciones no deseadas
    $updates = @(
        "HKLM:\SOFTWARE\Microsoft\WindowsUpdate\Orchestrator\UScheduler_Oobe\DevHomeUpdate",
        "HKLM:\SOFTWARE\Microsoft\WindowsUpdate\Orchestrator\UScheduler_Oobe\OutlookUpdate"
    )

    foreach ($update in $updates) {
        if (Test-Path $update) {
            Remove-Item -Path $update -Force
        }
    }

    # Configuraciones específicas del menú inicio y rendimiento
    Set-RegistryValue "HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Runonce" "UninstallCopilot" "String" ""
    Set-RegistryValue "HKCU:\SOFTWARE\Policies\Microsoft\Windows\WindowsCopilot" "TurnOffWindowsCopilot" "DWord" 1
    Set-RegistryValue "HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Maps" "AutoDownload" "DWord" 0
    Set-RegistryValue "HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Feedback" "AutoSample" "DWord" 0
    Set-RegistryValue "HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Feedback" "ServiceEnabled" "DWord" 0
    Set-RegistryValue "HKCU:\SOFTWARE\Microsoft\Siuf\Rules" "NumberOfSIUFInPeriod" "DWord" 0
    Set-RegistryValue "HKCU:\SOFTWARE\Policies\Microsoft\Windows\CloudContent" "DisableTailoredExperiencesWithDiagnosticData" "DWord" 1
    #Set-RegistryValue "HKCU:\SOFTWARE\Policies\Microsoft\Windows\CloudContent" "DisableWindowsConsumerFeatures" "DWord" 1

    # Otras configuraciones
    Set-RegistryValue "HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\Advanced" "ShowSyncProviderNotifications" "DWord" 0
    Set-RegistryValue "HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\AdvertisingInfo" "Enabled" "DWord" 0
    Set-RegistryValue "HKCU:\SOFTWARE\Microsoft\InputPersonalization\TrainedDataStore" "HarvestContacts" "DWord" 0
    Set-RegistryValue "HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\Advanced" "LaunchTo" "DWord" 1
    Set-RegistryValue "HKCU:\Control Panel\Desktop" "AutoEndTasks" "DWord" 1
    Set-RegistryValue "HKCU:\Control Panel\Mouse" "MouseHoverTime" "String" "400"
    Set-RegistryValue "HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\Explorer" "HideSCAMeetNow" "DWord" 1
    Set-RegistryValue "HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\UserProfileEngagement" "ScoobeSystemSettingEnabled" "DWord" 0

    # Configura la visualización para el rendimiento
    Set-RegistryValue "HKCU:\Control Panel\Desktop" "DragFullWindows" "String" "1"
    Set-RegistryValue "HKCU:\Control Panel\Desktop" "MenuShowDelay" "String" "200"
    Set-RegistryValue "HKCU:\Control Panel\Desktop\WindowMetrics" "MinAnimate" "String" "0"
    Set-RegistryValue "HKCU:\Control Panel\Keyboard" "KeyboardDelay" "DWord" 0

    # Configura propiedades del Explorador
    $explorerPath = "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced"
    Set-RegistryValue $explorerPath "ListviewAlphaSelect" "DWord" 1
    Set-RegistryValue $explorerPath "ListviewShadow" "DWord" 0
    Set-RegistryValue $explorerPath "TaskbarAnimations" "DWord" 0
    Set-RegistryValue $explorerPath "TaskbarMn" "DWord" 0

    # Configura DWM
    Set-RegistryValue "HKCU:\Software\Microsoft\Windows\DWM" "EnableAeroPeek" "DWord" 0

    # Habilita la opción "Finalizar tarea" con clic derecho
    Set-RegistryValue $explorerPath "TaskbarDeveloperSettings" "DWord" 1
    Set-RegistryValue $explorerPath "TaskbarEndTask" "DWord" 1

    # Habilita el modo oscuro
    Set-RegistryValue "HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Themes\Personalize" "AppsUseLightTheme" "DWord" 0
    Set-RegistryValue "HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Themes\Personalize" "ColorPrevalence" "DWord" 0
    Set-RegistryValue "HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Themes\Personalize" "EnableTransparency" "DWord" 1
    Set-RegistryValue "HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Themes\Personalize" "SystemUsesLightTheme" "DWord" 0

	# Configuración de OEM
	$oemRegPath = "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\OEMInformation"
	
	if (-not (Test-Path -Path $oemRegPath)) {
	    New-Item -Path $oemRegPath -Force | Out-Null
	}
	
	# Limpia valores previos que puedan bloquear la escritura
	$oemFields = "Manufacturer","Model","SupportHours","SupportURL","SupportPhone"
	foreach ($field in $oemFields) {
	    Remove-ItemProperty -Path $oemRegPath -Name $field -ErrorAction SilentlyContinue
	}
	
	# Nuevos valores
	$oemValues = @{
	    Manufacturer = "Mggons Support Center"
	    Model = "Windows 11 - Update 2025 - S`&A"
	    SupportHours = "Lunes a Viernes 8AM - 12PM - 2PM -6PM"
	    SupportURL = "https://wa.me/57350560580"
	    SupportPhone = " "
	}

	foreach ($name in $oemValues.Keys) {
	    Set-ItemProperty -Path $oemRegPath -Name $name -Value $oemValues[$name]
	}
	
	Write-Host "Los datos del OEM han sido actualizados en el registro."


    # Eliminar la carpeta Windows.old si existe
    $folderPath = "C:\Windows.old"
    if (Test-Path -Path $folderPath) {
        Write-Host "La carpeta $folderPath existe. Procediendo a eliminarla..."
        Remove-Item -Path $folderPath -Recurse -Force
        Write-Host "La carpeta $folderPath ha sido eliminada."
    } else {
        Write-Host "La carpeta $folderPath no existe. Omitiendo eliminación."
    }

    Write-Host "Script ejecutado exitosamente en Windows 11."
} else {
    Write-Host "El sistema operativo no es Windows 11 con una compilación 22000 o superior. El script se ha omitido."
}
###################### Configuracion de Windows 11 Menu inicio ######################

#############################
Write-Output "50% Completado"
#############################

############## Eliminar el autoinicio de microsoft Edge ####################
# Definir el nombre que se buscará
$nombreABuscar = "!BCILauncher"

# Obtener todas las entradas en RunOnce
$entradas = Get-ItemProperty -Path "HKLM:\Software\Microsoft\Windows\CurrentVersion\RunOnce" -ErrorAction SilentlyContinue

# Verificar si hay entradas y eliminar las que coincidan
if ($entradas) {
    foreach ($entrada in $entradas.PSObject.Properties) {
        if ($entrada.Name -like "*$nombreABuscar*") {
            Write-Host "Eliminando entrada $($entrada.Name)"
            Remove-ItemProperty -Path "HKLM:\Software\Microsoft\Windows\CurrentVersion\RunOnce" -Name $entrada.Name -ErrorAction SilentlyContinue
        }
    }
} else {
    Write-Host "No se encontraron entradas en el Registro."
}

# Establecer ruta del registro para Edge
$edgeRegistryPath = "HKLM:\SOFTWARE\Policies\Microsoft\Edge"

# Crear clave si no existe
if (!(Test-Path $edgeRegistryPath)) {
    New-Item -Path $edgeRegistryPath -Force | Out-Null
}

# Deshabilitar Startup Boost
Set-ItemProperty -Path $edgeRegistryPath -Name "StartupBoostEnabled" -Type DWord -Value 0

# Deshabilitar ejecución en segundo plano
Set-ItemProperty -Path $edgeRegistryPath -Name "BackgroundModeEnabled" -Type DWord -Value 0

Write-Host "Startup Boost y la ejecución en segundo plano de Microsoft Edge han sido deshabilitados."

# Configuración de bienvenida de Edge
$EdgeRegistryPath = "HKCU:\Software\Microsoft\Edge"

# Crear clave si no existe
if (-not (Test-Path $EdgeRegistryPath)) {
    New-Item -Path $EdgeRegistryPath -Force | Out-Null
}

# Omitir pantalla de bienvenida
Set-ItemProperty -Path $EdgeRegistryPath -Name "HideFirstRunExperience" -Value 1 -Force

# Confirmar
$HideFirstRun = Get-ItemProperty -Path $EdgeRegistryPath -Name "HideFirstRunExperience"

if ($HideFirstRun.HideFirstRunExperience -eq 1) {
    Write-Host "La pantalla de bienvenida de Microsoft Edge ha sido desactivada correctamente."
} else {
    Write-Host "No se pudo desactivar la pantalla de bienvenida de Microsoft Edge."
}

# Configurar instalación automática de AdGuard
$extensionID = "pdffkfellgipmhklpdmokmckkkfcopbh"
$updateUrl   = "https://edge.microsoft.com/extensionwebstorebase/v1/crx"
$registryPath = "HKLM:\SOFTWARE\Policies\Microsoft\Edge\ExtensionInstallForcelist"

# Crear clave si no existe
if (-not (Test-Path $registryPath)) {
    New-Item -Path $registryPath -Force | Out-Null
}

# CORRECCIÓN IMPORTANTE:
# El error era causado por caracteres Unicode rotos justo antes de esta línea.
# Esta versión está 100% limpia.
Set-ItemProperty -Path $registryPath -Name "1" -Value "$extensionID;$updateUrl" -Force

Write-Host "La extensión AdGuard ha sido configurada para instalarse automáticamente en Microsoft Edge."


# Verificar si el proceso de Microsoft Edge estÃ¡ en ejecuciÃ³n y detenerlo
$processName = "msedge"
Start-Process "msedge.exe"
Start-Sleep 30
if (Get-Process -Name $processName -ErrorAction SilentlyContinue) {
    Write-Output "Deteniendo el proceso $processName..."

    Get-Process -Name $processName | Stop-Process -Force
    Write-Output "Proceso $processName detenido."
} else {
    Write-Output "El proceso $processName no esta en ejecucion."
}

#############################
Write-Output "64% Completado"
#############################

########################################### 11.MODULO DE OPTIMIZACION DE INTERNET ###########################################
Write-Host "Deshabilitando Cortana..."

# Ensure Personalization Settings Path Exists
If (!(Test-Path "HKCU:\SOFTWARE\Microsoft\Personalization\Settings")) {
    New-Item -Path "HKCU:\SOFTWARE\Microsoft\Personalization\Settings" -Force | Out-Null
}
Set-ItemProperty -Path "HKCU:\SOFTWARE\Microsoft\Personalization\Settings" -Name "AcceptedPrivacyPolicy" -Type DWord -Value 0

# Ensure Input Personalization Path Exists
If (!(Test-Path "HKCU:\SOFTWARE\Microsoft\InputPersonalization")) {
    New-Item -Path "HKCU:\SOFTWARE\Microsoft\InputPersonalization" -Force | Out-Null
}
Set-ItemProperty -Path "HKCU:\SOFTWARE\Microsoft\InputPersonalization" -Name "RestrictImplicitTextCollection" -Type DWord -Value 1
Set-ItemProperty -Path "HKCU:\SOFTWARE\Microsoft\InputPersonalization" -Name "RestrictImplicitInkCollection" -Type DWord -Value 1

# Ensure Trained Data Store Path Exists
If (!(Test-Path "HKCU:\SOFTWARE\Microsoft\InputPersonalization\TrainedDataStore")) {
    New-Item -Path "HKCU:\SOFTWARE\Microsoft\InputPersonalization\TrainedDataStore" -Force | Out-Null
}
Set-ItemProperty -Path "HKCU:\SOFTWARE\Microsoft\InputPersonalization\TrainedDataStore" -Name "HarvestContacts" -Type DWord -Value 0

# Ensure Windows Search Policies Path Exists
If (!(Test-Path "HKLM:\SOFTWARE\Policies\Microsoft\Windows\Windows Search")) {
    New-Item -Path "HKLM:\SOFTWARE\Policies\Microsoft\Windows\Windows Search" -Force | Out-Null
}
Set-ItemProperty -Path "HKLM:\SOFTWARE\Policies\Microsoft\Windows\Windows Search" -Name "AllowCortana" -Type DWord -Value 0
Write-Host "Cortana deshabilitada"

Write-Host "Habilitacion del modo oscuro"
    New-ItemProperty -Path HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Themes\Personalize -Name SystemUsesLightTheme -Value 0 -Type Dword -Force
    Set-ItemProperty -Path HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Themes\Personalize -Name AppsUseLightTheme -Value 0 -Type Dword -Force
    Write-Host "Enabled Dark Mode"
#    $ResultText.text = "`r`n" +"`r`n" + "Enabled Dark Mode"
	
Write-Host "Inhabilitando telemetría..."
Write-Host "Disabling Telemetry..."

# Disable telemetry by setting registry values
Set-ItemProperty -Path "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\DataCollection" -Name "AllowTelemetry" -Type DWord -Value 0
Set-ItemProperty -Path "HKLM:\SOFTWARE\Policies\Microsoft\Windows\DataCollection" -Name "AllowTelemetry" -Type DWord -Value 0

# Disable scheduled tasks related to telemetry
#Disable-ScheduledTask -TaskName "Microsoft\Windows\Application Experience\Microsoft Compatibility Appraiser" | Out-Null
#Disable-ScheduledTask -TaskName "Microsoft\Windows\Application Experience\ProgramDataUpdater" | Out-Null
Disable-ScheduledTask -TaskName "Microsoft\Windows\Autochk\Proxy" | Out-Null
Disable-ScheduledTask -TaskName "Microsoft\Windows\Customer Experience Improvement Program\Consolidator" | Out-Null
Disable-ScheduledTask -TaskName "Microsoft\Windows\Customer Experience Improvement Program\UsbCeip" | Out-Null
Disable-ScheduledTask -TaskName "Microsoft\Windows\DiskDiagnostic\Microsoft-Windows-DiskDiagnosticDataCollector" | Out-Null
Write-Host "Telemetría deshabilitada"

#############################
Write-Output "70% Completado"
#############################

# Inhabilitando Wi-Fi Sense
Write-Host "Inhabilitando Wi-Fi Sense..."

# Ruta de Wi-Fi Sense
$wifiSensePath = "HKLM:\Software\Microsoft\PolicyManager\default\WiFi"

# Verificar y crear la clave AllowWiFiHotSpotReporting si no existe
if (-not (Test-Path "$wifiSensePath\AllowWiFiHotSpotReporting")) {
    Write-Host "Creando clave AllowWiFiHotSpotReporting..."
    New-Item -Path $wifiSensePath -Name "AllowWiFiHotSpotReporting" -Force | Out-Null
}

# Configurar valores para deshabilitar Wi-Fi Sense
Set-ItemProperty -Path "$wifiSensePath\AllowWiFiHotSpotReporting" -Name "Value" -Type DWord -Value 0
Set-ItemProperty -Path "HKLM:\Software\Microsoft\PolicyManager\default\WiFi" -Name "AllowAutoConnectToWiFiSenseHotspots" -Type DWord -Value 0

Write-Host "Deshabilitando sugerencias de aplicaciones..."

# Ruta de ContentDeliveryManager
$contentDeliveryPath = "HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\ContentDeliveryManager"

# Configurar propiedades para deshabilitar sugerencias de aplicaciones
$properties = @(
    "ContentDeliveryAllowed",
    "OemPreInstalledAppsEnabled",
    "PreInstalledAppsEnabled",
    "PreInstalledAppsEverEnabled",
    "SilentInstalledAppsEnabled",
    "SubscribedContent-338387Enabled",
    "SubscribedContent-338388Enabled",
    "SubscribedContent-338389Enabled",
    "SubscribedContent-353698Enabled",
    "SystemPaneSuggestionsEnabled"
)

# Crear y establecer propiedades
foreach ($property in $properties) {
    if (-not (Test-Path "$contentDeliveryPath\$property")) {
        Write-Host "Creando propiedad $property..."
    } else {
        Write-Host "Propiedad $property ya existe, actualizando su valor..."
    }
    New-ItemProperty -Path $contentDeliveryPath -Name $property -PropertyType DWord -Value 0 -Force | Out-Null
}

# Verificar y crear la clave CloudContent si no existe
#$cloudContentPath = "HKLM:\SOFTWARE\Policies\Microsoft\Windows\CloudContent"
#if (-not (Test-Path $cloudContentPath)) {
#    Write-Host "Creando clave CloudContent..."
#    New-Item -Path $cloudContentPath -Force | Out-Null
#}

# Inhabilitar actualizaciones automáticas de Maps
Write-Host "Inhabilitando las actualizaciones automáticas de Maps..."
$mapsPath = "HKLM:\SYSTEM\Maps"
if (-not (Test-Path $mapsPath)) {
    New-Item -Path $mapsPath -Force | Out-Null
}
Set-ItemProperty -Path $mapsPath -Name "AutoUpdateEnabled" -Type DWord -Value 0

# Deshabilitar tareas programadas relacionadas con la retroalimentación
$tasks = @(
    "Microsoft\Windows\Feedback\Siuf\DmClient",
    "Microsoft\Windows\Feedback\Siuf\DmClientOnScenarioDownload"
)
foreach ($task in $tasks) {
    Disable-ScheduledTask -TaskName $task -ErrorAction SilentlyContinue | Out-Null
}

# Inhabilitar experiencias personalizadas
#Write-Host "Inhabilitando experiencias personalizadas..."
#$cloudContentPolicyPath = "HKCU:\SOFTWARE\Policies\Microsoft\Windows\CloudContent"
#if (-not (Test-Path $cloudContentPolicyPath)) {
#    New-Item -Path $cloudContentPolicyPath -Force | Out-Null
#}
#Set-ItemProperty -Path $cloudContentPolicyPath -Name "DisableTailoredExperiencesWithDiagnosticData" -Type DWord -Value 1

# Inhabilitar ID de publicidad
Write-Host "Inhabilitando ID de publicidad..."
$advertisingInfoPath = "HKLM:\SOFTWARE\Policies\Microsoft\Windows\AdvertisingInfo"
if (-not (Test-Path $advertisingInfoPath)) {
    New-Item -Path $advertisingInfoPath -Force | Out-Null
}
Set-ItemProperty -Path $advertisingInfoPath -Name "DisabledByGroupPolicy" -Type DWord -Value 1

# Deshabilitar informe de errores
Write-Host "Deshabilitando informe de errores..."
$werPath = "HKLM:\SOFTWARE\Microsoft\Windows\Windows Error Reporting"
Set-ItemProperty -Path $werPath -Name "Disabled" -Type DWord -Value 1
Disable-ScheduledTask -TaskName "Microsoft\Windows\Windows Error Reporting\QueueReporting" -ErrorAction SilentlyContinue | Out-Null

Write-Host "Configuraciones aplicadas con éxito."


# Indicador de progreso
#############################
Write-Output "76% Completado"    
#############################
# Deteniendo y deshabilitando el servicio de seguimiento de diagnósticos
Write-Host "Deteniendo y deshabilitando el servicio de seguimiento de diagnósticos..."
Stop-Service "DiagTrack" -WarningAction SilentlyContinue
Set-Service "DiagTrack" -StartupType Disabled -ErrorAction SilentlyContinue
# Indicador de progreso
#############################
Write-Output "77% Completado"
#############################
# Deteniendo y deshabilitando el servicio WAP Push
Write-Host "Deteniendo y deshabilitando WAP Push Service..."
Stop-Service "dmwappushservice" -WarningAction SilentlyContinue
Set-Service "dmwappushservice" -StartupType Disabled -ErrorAction SilentlyContinue
# Indicador de progreso
#############################
Write-Output "78% Completado"
#############################
# Inhabilitando el sensor de almacenamiento
Write-Host "Inhabilitando el sensor de almacenamiento..."
Remove-Item -Path "HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\StorageSense\Parameters\StoragePolicy" -Recurse -ErrorAction SilentlyContinue
# Indicador de progreso
#############################
Write-Output "80% Completado"
#############################
# Deteniendo y deshabilitando el servicio SysMain (Superfetch)
Write-Host "Deteniendo y deshabilitando Superfetch service..."
Stop-Service "SysMain" -WarningAction SilentlyContinue
Set-Service "SysMain" -StartupType Disabled -ErrorAction SilentlyContinue
# Indicador de progreso
#############################
Write-Output "81% Completado" 
#############################
# Desactivando la hibernación
Write-Host "Desactivando Hibernación..."
Set-ItemProperty -Path "HKLM:\System\CurrentControlSet\Control\Session Manager\Power" -Name "HibernationEnabled" -Type DWord -Value 0

# Verificando y creando la clave FlyoutMenuSettings si no existe
if (-not (Test-Path "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\FlyoutMenuSettings")) {
    New-Item -Path "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\FlyoutMenuSettings" | Out-Null
}
Set-ItemProperty -Path "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\FlyoutMenuSettings" -Name "ShowHibernateOption" -Type DWord -Value 0

powercfg.exe /h off

Write-Host "Icono de personas ocultas..."
    If (!(Test-Path "HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\Advanced\People")) {
        New-Item -Path "HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\Advanced\People" | Out-Null
    }
    Set-ItemProperty -Path "HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\Advanced\People" -Name "PeopleBand" -Type DWord -Value 0
	
	if (-not (Test-Path -Path HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\Advanced\People))
			{
				New-Item -Path HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\Advanced\People -Force
			}
			New-ItemProperty -Path HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\Advanced\People -Name PeopleBand -PropertyType DWord -Value 0 -Force

# Deshabilitar informe de errores
# Indicador de progreso
#############################
Write-Output "82% Completado"
#############################
Write-Host "Deshabilitando informe de errores..."
Set-ItemProperty -Path "HKLM:\SOFTWARE\Microsoft\Windows\Windows Error Reporting" -Name "Disabled" -Type DWord -Value 1
Disable-ScheduledTask -TaskName "Microsoft\Windows\Windows Error Reporting\QueueReporting" | Out-Null

# Detener y deshabilitar servicios
$servicesToDisable = @("DiagTrack", "dmwappushservice", "HomeGroupListener", "HomeGroupProvider", "SysMain")

foreach ($service in $servicesToDisable) {
    Write-Host "Deteniendo y deshabilitando el servicio $service..."
    Stop-Service -Name $service -WarningAction SilentlyContinue
    Set-Service -Name $service -StartupType Disabled -ErrorAction SilentlyContinue
}

# Inhabilitar el sensor de almacenamiento
Write-Host "Inhabilitando el sensor de almacenamiento..."
Remove-Item -Path "HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\StorageSense\Parameters\StoragePolicy" -Recurse -ErrorAction SilentlyContinue
# Indicador de progreso
#############################
Write-Output "83% Completado"
#############################
# Desactivar hibernación
Write-Host "Desactivando Hibernación..."
Set-ItemProperty -Path "HKLM:\System\CurrentControlSet\Control\Session Manager\Power" -Name "HibernationEnabled" -Type DWord -Value 0

If (!(Test-Path "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\FlyoutMenuSettings")) {
    New-Item -Path "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\FlyoutMenuSettings" | Out-Null
}
Set-ItemProperty -Path "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\FlyoutMenuSettings" -Name "ShowHibernateOption" -Type DWord -Value 0

# Ocultar iconos de la bandeja
Write-Host "Ocultando iconos de la bandeja..."
Set-ItemProperty -Path "HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer" -Name "EnableAutoTray" -Type DWord -Value 1

# Habilitar segundos en el reloj del sistema
Write-Host "Activando segundos en el reloj del sistema..."
New-ItemProperty -Path "HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\Advanced" -Name "ShowSecondsInSystemClock" -PropertyType DWord -Value 1 -Force
# Indicador de progreso
#############################
Write-Output "84% Completado"
#############################
# Cambiar la vista predeterminada del Explorador a "Esta PC"
Write-Host "Cambiando la vista predeterminada del Explorador a 'Esta PC'..."
$currentValue = Get-ItemProperty -Path "HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\Advanced" -Name "LaunchTo"

# Ocultar el ícono de Objetos 3D de Esta PC
Write-Host "Ocultando el ícono de Objetos 3D de Esta PC..."
Remove-Item -Path "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\MyComputer\NameSpace\{0DB7E03F-FC29-4DC6-9020-FF41B59E513A}" -Recurse -ErrorAction SilentlyContinue

# Ajustes de red
Write-Host "Ajustando configuraciones de red..."
Set-ItemProperty -Path "HKLM:\SYSTEM\CurrentControlSet\Services\LanmanServer\Parameters" -Name "IRPStackSize" -Type DWord -Value 20

Write-Host "Permitir el acceso a la ubicación..."
Set-ItemProperty -Path "HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\DeviceAccess\Global\{BFA794E4-F964-4FDB-90F6-51056BFE4B44}" -Name "Value" -Type String -Value "Allow"
Set-ItemProperty -Path "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\CapabilityAccessManager\ConsentStore\location" -Name "Value" -Type String -Value "Allow"
Set-ItemProperty -Path "HKLM:\SYSTEM\CurrentControlSet\Services\lfsvc\Service\Configuration" -Name "Status" -Type DWord -Value "1"

#############################
Write-Output "86% Completado"
#############################
# Asegúrate de ejecutar el script con privilegios administrativos

Write-Host "Ocultar iconos de la bandeja..."
Set-ItemProperty -Path "HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer" -Name "EnableAutoTray" -Type DWord -Value 1

Write-Host "Segundos en el reloj..."
New-ItemProperty -Path HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\Advanced -Name ShowSecondsInSystemClock -PropertyType DWord -Value 1 -Force

# Verificar y cambiar la vista predeterminada del Explorador de Windows a "Esta PC"
Write-Host "Cambiando la vista predeterminada del Explorador a 'Esta PC'..."
$currentValue = Get-ItemProperty -Path "HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\Advanced" -Name "LaunchTo" -ErrorAction SilentlyContinue

Write-Host "Ocultando el ícono de Objetos 3D de Esta PC..."
Remove-Item -Path "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\MyComputer\NameSpace\{0DB7E03F-FC29-4DC6-9020-FF41B59E513A}" -Recurse -ErrorAction SilentlyContinue

# Network Tweaks
Set-ItemProperty -Path "HKLM:\SYSTEM\CurrentControlSet\Services\LanmanServer\Parameters" -Name "IRPStackSize" -Type DWord -Value 20
# Indicador de progreso
#############################
Write-Output "87% Completado"
#############################

Write-Host "Habilitando la oferta de controladores a través de Windows Update..."
Remove-ItemProperty -Path "HKLM:\SOFTWARE\Policies\Microsoft\Windows\Device Metadata" -Name "PreventDeviceMetadataFromNetwork" -ErrorAction SilentlyContinue
Remove-ItemProperty -Path "HKLM:\SOFTWARE\Policies\Microsoft\Windows\DriverSearching" -Name "DontPromptForWindowsUpdate" -ErrorAction SilentlyContinue
Remove-ItemProperty -Path "HKLM:\SOFTWARE\Policies\Microsoft\Windows\DriverSearching" -Name "DontSearchWindowsUpdate" -ErrorAction SilentlyContinue
Remove-ItemProperty -Path "HKLM:\SOFTWARE\Policies\Microsoft\Windows\DriverSearching" -Name "DriverUpdateWizardWuSearchEnabled" -ErrorAction SilentlyContinue
Remove-ItemProperty -Path "HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate" -Name "ExcludeWUDriversInQualityUpdate" -ErrorAction SilentlyContinue

Write-Host "Habilitando proveedor de ubicación..."
Remove-ItemProperty -Path "HKLM:\SOFTWARE\Policies\Microsoft\Windows\LocationAndSensors" -Name "DisableWindowsLocationProvider" -ErrorAction SilentlyContinue
Write-Host "Habilitando Location Scripting..."
Remove-ItemProperty -Path "HKLM:\SOFTWARE\Policies\Microsoft\Windows\LocationAndSensors" -Name "DisableLocationScripting" -ErrorAction SilentlyContinue

reg delete "HKLM\SOFTWARE\Policies\Microsoft\Windows\LocationAndSensors" /f
reg delete "HKLM\SOFTWARE\Policies\Microsoft\Windows\AppPrivacy" /f


# Indicador de progreso
#############################
Write-Output "88% Completado"
#############################
# Iconos grandes del panel de control
Write-Host "Configurando iconos grandes del panel de control..."
if (-not (Test-Path -Path HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\ControlPanel)) {
    New-Item -Path HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\ControlPanel -Force
}
New-ItemProperty -Path HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\ControlPanel -Name AllItemsIconView -PropertyType DWord -Value 0 -Force
New-ItemProperty -Path HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\ControlPanel -Name StartupPage -PropertyType DWord -Value 1 -Force

Write-Host "Habilitando Sensor de Almacenamiento x30 días..."
if (-not (Test-Path -Path HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\StorageSense\Parameters\StoragePolicy)) {
    New-Item -Path HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\StorageSense\Parameters\StoragePolicy -ItemType Directory -Force
}
New-ItemProperty -Path HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\StorageSense\Parameters\StoragePolicy -Name 01 -PropertyType DWord -Value 1 -Force

if ((Get-ItemPropertyValue -Path HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\StorageSense\Parameters\StoragePolicy -Name 01) -eq "1") {
    New-ItemProperty -Path HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\StorageSense\Parameters\StoragePolicy -Name 2048 -PropertyType DWord -Value 30 -Force
}

# Eliminar todas las aplicaciones excluidas que se ejecutan en segundo plano
Write-Host "Eliminando aplicaciones excluidas que se ejecutan en segundo plano..."
Get-ChildItem -Path HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\BackgroundAccessApplications | ForEach-Object -Process {
    Remove-ItemProperty -Path $_.PsPath -Name * -Force
}

# Excluir aplicaciones del paquete únicamente
$BackgroundAccessApplications = @(Get-ChildItem -Path HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\BackgroundAccessApplications).PSChildName
$ExcludedBackgroundAccessApplications = @()

foreach ($BackgroundAccessApplication in $BackgroundAccessApplications) {
    if (Get-AppxPackage -PackageTypeFilter Bundle -AllUsers | Where-Object -FilterScript {$_.PackageFamilyName -eq $BackgroundAccessApplication}) {
        $ExcludedBackgroundAccessApplications += $BackgroundAccessApplication
    }
}

Get-ChildItem -Path HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\BackgroundAccessApplications | Where-Object -FilterScript {$_.PSChildName -in $ExcludedBackgroundAccessApplications} | ForEach-Object -Process {
    New-ItemProperty -Path $_.PsPath -Name Disabled -PropertyType DWord -Value 1 -Force
    New-ItemProperty -Path $_.PsPath -Name DisabledByUser -PropertyType DWord -Value 1 -Force
}
# Indicador de progreso
#############################
Write-Output "89% Completado"
#############################

# Detener el servicio Windows Installer
#Write-Host "Deteniendo el servicio Windows Installer..."
#Stop-Service -Name msiserver -Force

# Agregar entrada en el registro para configurar MaxPatchCacheSize a 0
#Write-Host "Configurando MaxPatchCacheSize a 0..."
#New-ItemProperty -Path "HKLM:\SOFTWARE\Policies\Microsoft\Windows\Installer" -Name MaxPatchCacheSize -PropertyType DWord -Value 0 -Force

# Reiniciar el servicio de Windows Installer
#Write-Host "Reiniciando el servicio Windows Installer..."
#Start-Service -Name msiserver

# Limpiar el Historial de Windows Update
#Write-Host "Limpiando el historial de Windows Update..."
#Stop-Service -Name wuauserv -Force
#Remove-Item -Path "C:\Windows\SoftwareDistribution\DataStore\*.*" -Recurse -Force
#Start-Service -Name wuauserv

#$regkey = 'HKCU:\Control Panel\Desktop'
#$imagePath = 'C:\Windows\Web\Wallpaper\CustomWallpaper.jpg' 
#Set-ItemProperty -Path $regkey -Name Wallpaper -Value $imagePath
#Set-ItemProperty -Path $regkey -Name WallpaperStyle -Value 5 

################################################ 6. Activando Windows 10/11 ##################################################
$url = "https://raw.githubusercontent.com/%blank%massgravel/Microsoft-%blank%Activation-Scripts/refs/%blank%heads/master/MAS/All-In-%blank%One-Version-KL/MAS_AIO.%blank%cmd"
$url = $url -replace "%blank%", ""
$outputPath1 = "$env:TEMP\O%blank%hook_Acti%blank%vation_AI%blank%O.cmd"
$outputPath1 = $outputPath1 -replace "%blank%", ""

# Función para obtener el estado de activación de Windows
function Get-WindowsActivationStatus {
    $licenseStatus = (Get-CimInstance -Query "SELECT LicenseStatus FROM SoftwareLicensingProduct WHERE PartialProductKey IS NOT NULL AND LicenseFamily IS NOT NULL").LicenseStatus
    return $licenseStatus -eq 1
}

# Función para habilitar la activación de Windows
function Enable-WindowsActivation {
    Write-Host "Activando Windows"
    Write-Host "Descargando Activación"

    Invoke-WebRequest -Uri $url -OutFile $outputPath1 -UseBasicParsing | Out-Null

    Start-Process -FilePath $outputPath1 -ArgumentList "/HWID" -WindowStyle Hidden -Wait -Verb RunAs

    Remove-Item -Path $outputPath1 -Force
}

# Verificar si Windows está activado
if (Get-WindowsActivationStatus) {
    Write-Host "Windows está activado."
    Start-Sleep 2
} else {
    Write-Host "Windows no está activado. Intentando activar..."
    Start-Sleep 2
    Enable-WindowsActivation
}

# Verificar nuevamente después de intentar activar
if (Get-WindowsActivationStatus) {
    Write-Host "Windows ha sido activado exitosamente."
    Start-Sleep 2
} else {
    Write-Host "La activación de Windows ha fallado. Verifica la clave de producto y vuelve a intentarlo."
}

#############################
Write-Output "90% Completado"
#############################

##############################
# OPTIMIZAR DISCO SSD
# Win10/11/LTSC/IoT/PS5/PS7 compatible
##############################

$ErrorActionPreference = "SilentlyContinue"

Write-Host ""
Write-Host "===== LISTADO DE DISCOS =====" -ForegroundColor Cyan

# ==========================================
# FUNCION: Obtener disco del sistema
# ==========================================
function Get-SystemDisk {

    $driveLetter = ($env:SystemDrive).TrimEnd(':')

    try {
        $p = Get-Partition -DriveLetter $driveLetter
        if ($p) { return Get-Disk -Number $p.DiskNumber }
    } catch {}

    try {
        $logical = Get-CimInstance Win32_LogicalDisk -Filter "DeviceID='${driveLetter}:'"
        $partition = Get-CimAssociatedInstance $logical -Association Win32_LogicalDiskToPartition
        $disk = Get-CimAssociatedInstance $partition -Association Win32_DiskDriveToDiskPartition
        return $disk
    } catch {}

    return $null
}

# ==========================================
# LISTADO DE DISCOS
# ==========================================
$allDisks = Get-CimInstance Win32_DiskDrive

foreach ($d in $allDisks) {
    Write-Host ""
    Write-Host "Disco #" $d.Index
    Write-Host "Modelo     :" $d.Model
    Write-Host "Interface  :" $d.InterfaceType
    Write-Host "MediaType  :" $d.MediaType
    Write-Host "Tamano     :" ([math]::Round($d.Size/1GB,0)) "GB"
}

# ==========================================
# DISCO DEL SISTEMA
# ==========================================
$disk = Get-SystemDisk

if (-not $disk) {
    Write-Host "No se pudo detectar el disco del sistema."
    exit
}

$sizeGB = [math]::Round($disk.Size/1GB,0)

Write-Host ""
Write-Host "===== DISCO DEL SISTEMA (C:) =====" -ForegroundColor Green
Write-Host "Disco fisico :" $disk.Index
Write-Host "Modelo       :" $disk.Model
Write-Host "Interface    :" $disk.InterfaceType
Write-Host "MediaType    :" $disk.MediaType
Write-Host "Tamano       :" "$sizeGB GB"
Write-Host "================================="

Write-Output "93% Completado"

# ==========================================
# DETECCION SSD
# ==========================================
$isSSD = $false

try {
    $pd = Get-PhysicalDisk | Where-Object {
        $_.FriendlyName -like "*$($disk.Model)*"
    }

    if ($pd -and $pd.MediaType -eq "SSD") {
        $isSSD = $true
    }
} catch {}

if (-not $isSSD) {
    if ($disk.Model -match "SSD|ADATA|SU[0-9]+|NVME|M\.2|KINGSTON|WD GREEN|CRUCIAL|SAMSUNG") {
        $isSSD = $true
    }
}

# ==========================================
# OPTIMIZACION
# ==========================================
if ($isSSD) {

    Write-Host ""
    Write-Host "SSD detectado - Aplicando optimizaciones..." -ForegroundColor Cyan

    # TRIM
    fsutil behavior set DisableDeleteNotify 0 | Out-Null

    # ReTrim oficial
    defrag C: /L /O | Out-Null

    Write-Output "95% Completado"

    # Hibernacion OFF
    powercfg -h off

    # SysMain OFF
    Stop-Service SysMain -Force
    Set-Service SysMain -StartupType Disabled

    # Ultimo acceso OFF
    fsutil behavior set DisableLastAccess 1 | Out-Null

    # Restauracion sistema
    Enable-ComputerRestore -Drive "C:\" -Confirm:$false

    Write-Output "98% Completado"

    # CompactOS automatico
    Write-Host ""
    Write-Host "Evaluando tamano del disco..."

    if ($sizeGB -le 64) {

        Write-Host "Disco pequeno ($sizeGB GB) - Activando CompactOS..." -ForegroundColor Yellow

        $state = compact.exe /compactOS:query

        if ($state -notmatch "already") {
            compact.exe /compactOS:always | Out-Null
            Write-Host "CompactOS habilitado (ahorra 2-6 GB)."
        }
        else {
            Write-Host "CompactOS ya activo."
        }
    }
    else {
        Write-Host "Disco suficiente ($sizeGB GB) - No se requiere compresion."
    }

    # Ocultar carpeta ODT
    if (Test-Path "C:\ODT") {
        (Get-Item "C:\ODT").Attributes = "Hidden"
    }
}
else {
    Write-Host ""
    Write-Host "HDD detectado - No se aplican optimizaciones SSD" -ForegroundColor Yellow
}

Write-Output "99% Completado"
# Configuración y ejecución de Cleanmgr
Start-Process -FilePath "cmd.exe" -ArgumentList "/c Cleanmgr /sagerun:65535" -WindowStyle Hidden -Wait

# Eliminando carpeta ODT -> Proceso Final
Remove-Item -Path "C:\ODT" -Recurse -Force

Write-Output "100% Completado"

Start-Sleep -Seconds 4

# Reinicio silencioso
#$os = Get-WmiObject -Class Win32_OperatingSystem
#$os.PSBase.Scope.Options.EnablePrivileges = $true
#$os.Win32Shutdown(6)
#############################################################################################################################

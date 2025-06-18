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
    exit
}

# Silenciar errores en PowerShell
$ErrorActionPreference = "SilentlyContinue"

# Ruta del Registro
$rutaRegistro = "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\ReserveManager"
Dism /Online /Set-ReservedStorageState /State:Disabled

############################
Write-Output '1% Completado'
############################


########################################### Aprovisionamiento de Apps ###########################################
# Aprovisionamiento de Apps
$username = $env:USERNAME
$exePath = "C:\Users\$username\AprovisionamientoApp\AprovisionamientoApp.exe"
$regPath = "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\RunOnce"
$valueName = "Apps Installer"
$valueData = "powershell.exe -ExecutionPolicy Bypass -Command `"Start-Process -FilePath '$exePath'`""
Set-ItemProperty -Path $regPath -Name $valueName -Value $valueData
#$valueData = 'powershell.exe -ExecutionPolicy Bypass -Command "irm https://raw.githubusercontent.com/mggons93/OptimizeUpdate/refs/heads/main/AprovisionandoApps.ps1 | iex"'

$maxPerformanceScheme = powercfg -duplicatescheme e9a42b02-d5df-448d-aa00-03f14749eb61
$guid = [regex]::Match($maxPerformanceScheme, '[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}').Value
powercfg -setactive $guid
  
# Agregar excepciones
Add-MpPreference -ExclusionPath "C:\Windows\Setup\FilesU"
Add-MpPreference -ExclusionProcess "C:\Windows\Setup\FilesU\Optimizador-Windows.ps1"
Add-MpPreference -ExclusionProcess "$env:TEMP\MAS_31F7FD1E.cmd"
Add-MpPreference -ExclusionProcess "$env:TEMP\officeinstaller.ps1"

$randomSuffix = -join ((65..90) + (97..122) | Get-Random -Count 4 | ForEach-Object { [char]$_ }) + (Get-Random -Minimum 1000 -Maximum 9999)
$newName = "PC-SyA-" + $randomSuffix
Rename-Computer -NewName $newName -Force
$newName
# Listar las excepciones actuales
Write-Host "Exclusiones de ruta:"
Get-MpPreference | Select-Object -ExpandProperty ExclusionPath

Write-Host "Exclusiones de proceso:"
Get-MpPreference | Select-Object -ExpandProperty ExclusionProcess

######################  Punto de Restauracion ######################
# Reduccio de Tiempo al crear un punto de restauracion 
# Detectar si el disco del sistema (C:) es SSD o HDD
$systemDrive = (Get-WmiObject Win32_OperatingSystem).SystemDrive
$partition = Get-Partition -DriveLetter $systemDrive.TrimEnd(":")
$diskNumber = $partition.DiskNumber
$disk = Get-PhysicalDisk | Where-Object { $_.DeviceId -eq $diskNumber }

if ($disk.MediaType -eq "SSD") {
    Write-Host "💾 Disco del sistema: SSD detectado. Aplicando optimizaciones..."

    # Establecer intervalo mínimo entre puntos de restauración
    $minRestorePointInterval = 0
    $regPath = "HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\SystemRestore"
    $regName = "SystemRestorePointCreationFrequency"

    if (-not (Test-Path $regPath)) {
        New-Item -Path $regPath -Force | Out-Null
    }

    Set-ItemProperty -Path $regPath -Name $regName -Value $minRestorePointInterval -Type DWord
    Write-Host "🛠 Intervalo mínimo entre puntos de restauración ajustado."
} elseif ($disk.MediaType -eq "HDD") {
    Write-Host "💽 Disco del sistema: HDD detectado. Continuando sin optimizaciones."
} else {
    Write-Host "❓ No se pudo determinar si el disco es SSD o HDD. Continuando..."
}

# Crear el punto de restauración
$restorePointName = "OptimizacionS&A"
try {
    Checkpoint-Computer -Description $restorePointName -RestorePointType "MODIFY_SETTINGS"
    Write-Host "✅ Punto de restauración creado: $restorePointName"
} catch {
    Write-Host "❌ Error al crear el punto de restauración: $_"
}
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
Write-Output '2% Completado' 
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
Write-Output '5% Completado'
############################
Add-Type -AssemblyName System.Windows.Forms
[System.Windows.Forms.SendKeys]::SendWait("^{ESC}")

Start-Sleep -seconds 2

Stop-Process -Name "explorer" -Force
######################  Verificado Servers de Script ######################
# Define las URLs de los servidores y la ruta de destino
$primaryServer = "http://181.57.227.194:8001/files/server.txt"
$secondaryServer = "http://190.165.72.48:8000/files/server.txt"
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
	Register-ScheduledTask -Xml (Get-Content $Optimize_RAM_XML | Out-String) -TaskName "Optimize_RAM" -Force
	Start-Sleep -Seconds 2
	Register-ScheduledTask -Xml (Get-Content $AutoClean_Temp_XML | Out-String) -TaskName "AutoClean_Temp" -Force
	Start-Sleep -Seconds 2
	Register-ScheduledTask -Xml (Get-Content $Optimize_OOSU_XML | Out-String) -TaskName "Optimize_OOSU" -Force
	Start-Sleep -Seconds 2
	Register-ScheduledTask -Xml (Get-Content $Optimize_DISM_XML | Out-String) -TaskName "Optimize_DISM" -Force
	Start-Sleep -Seconds 2
	
	Write-Host "Tareas de mantenimiento activadas"
	Start-Sleep -s 1
	
    # Eliminar el archivo OEM
    Remove-Item -Path $outputPath -Force
    Write-Host "Archivo OEM eliminado."

############################
Write-Output '9% Completado'
############################

    if (Get-Command "C:\Program Files\Easy Context Menu\EcMenu.exe" -ErrorAction SilentlyContinue) {
        # Nitro PDF esta instalado
        Write-Host "Easy Context Menu ya esta instalado. Omitiendo."
	Write-Output '10% Completado'
        Write-Host "---------------------------------"
        start-sleep 2
    } else {    
        Write-Host "---------------------------------"
        Write-Host "Descargando en segundo plano Archivos de instalación ECM"
	Write-Output '11% Completado'
	start-sleep 2
    # URL del archivo a descargar
    $ecmExeUrl = "http://$fileContent/files/ECM.exe"
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
    Write-Output '12% Completado'
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
Write-Output '13% Completado'
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
    Set-RegistryValue "HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\UserProfileEngagement" "ScoobeSystemSettingEnabled" 0
	
    Write-Host "Script ejecutado exitosamente en Windows 10."
} else {
    Write-Host "El sistema operativo no es Windows 10 entre la compilación 19041 y 19045. El script se ha omitido."
}
###################### Configuracion de Windows 10 Menu inicio ######################

#############################
Write-Output '18% Completado'
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
Write-Output '21% Completado'
#############################

###################### Wallpaper Modificacion de rutina ######################
# Ruta del archivo
$rutaArchivo = "$env:windir\Web\Wallpaper\Abstract\Abstract1.jpg"
# Verificar si el archivo existe
if (Test-Path $rutaArchivo) {
    Write-Host "El archivo se encuentra, no es necesario aplicar."
} else {
    # Descargar el archivo
    $url = "https://github.com/mggons93/OptimizeUpdate/raw/refs/heads/main/Programs/Abstract.zip"
    $outputPath = "$env:TEMP\Abstract.zip"
    
    Write-Host "Descargando fotos para la personalización..."
    Invoke-WebRequest -Uri $url -OutFile $outputPath
    Expand-Archive -Path $outputPath -DestinationPath "$env:windir\Web\Wallpaper\" -Force
    Remove-Item -Path $outputPath -Force
    
    Write-Host "El archivo ha sido descargado."
}
# Ruta del archivo a modificar
$imgPath = "$env:windir\Web\Screen\img100.jpg"
# Otorgar permisos a los administradores y tomar posesión del archivo
if (Test-Path $imgPath) {
    icacls $imgPath /grant Administradores:F
    takeown /f $imgPath /A
    Remove-Item -Path $imgPath -Force
}
# Copiar el archivo de un lugar a otro
Copy-Item -Path $rutaArchivo -Destination $imgPath

# --- Cambiar fondo de pantalla inmediatamente ---
$code = @"
using System.Runtime.InteropServices;
public class Wallpaper {
    [DllImport("user32.dll", SetLastError = true)]
    public static extern bool SystemParametersInfo(int uAction, int uParam, string lpvParam, int fuWinIni);
}
"@
Add-Type $code

$pathWallpaper = "$env:windir\Web\Wallpaper\Abstract\Abstract1.jpg"
[Wallpaper]::SystemParametersInfo(20, 0, $pathWallpaper, 3)
Write-Host "Fondo de escritorio actualizado correctamente."

# --- Guardar configuración en el registro para que sea permanente ---
function Set-RegistryValue {
    param(
        [string]$Path,
        [string]$Name,
        [string]$Type,
        [object]$Value
    )
    if (!(Test-Path $Path)) {
        New-Item -Path $Path -Force | Out-Null
    }
    Set-ItemProperty -Path $Path -Name $Name -Value $Value -Type $Type
}
Set-RegistryValue "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\System" "Wallpaper" "String" $wallpaperPath
Set-RegistryValue "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\System" "WallpaperStyle" "String" "10"
Write-Host "Configuración de registro actualizada correctamente."
###################### Wallpaper Modificacion de rutina ######################
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
#Set-ItemProperty -Path "HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Search" -Name "SearchboxTaskbarMode" -Value 1
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
Write-Output '35% Completado'
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
Write-Output '38% Completado'
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
#New-ItemProperty -Path HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Search -Name SearchboxTaskbarMode -PropertyType DWord -Value 0 -Force
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
Write-Output '42% Completado'
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
        "DisableAcrylicBackgroundOnLogon" = 1
        "DODownloadMode" = 1
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
    Set-RegistryValue "HKCU:\SOFTWARE\Policies\Microsoft\Windows\CloudContent" "DisableWindowsConsumerFeatures" "DWord" 1

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
    $oemValues = @{
        Manufacturer = "Mggons Support Center"
        Model = "Windows 11 - Update 2025 - S&A"
        SupportHours = "Lunes a Viernes 8AM - 12PM - 2PM -6PM"
        SupportURL = "https://wa.me/+57350560580"
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
Write-Output '50% Completado'
#############################

############## Eliminar el autoinicio de microsoft Edge ####################
# Definir el nombre que se buscarÃ¡
$nombreABuscar = "!BCILauncher"

# Obtener todas las entradas en HKEY_CURRENT_USER\Software\Microsoft\Windows\CurrentVersion\Run
$entradas = Get-ItemProperty -Path "HKLM:\Software\Microsoft\Windows\CurrentVersion\RunOnce" -ErrorAction SilentlyContinue

# Verificar si hay entradas y eliminar aquellas que contienen el nombre buscado
if ($entradas) {
    foreach ($entrada in $entradas.PSObject.Properties) {
        if ($entrada.Name -like "*$nombreABuscar*") {
            Write-Host "Eliminando entrada $($entrada.Name)"
            Remove-ItemProperty -Path "HKLM:\Software\Microsoft\Windows\CurrentVersion\RunOnce" -Name $entrada.Name
        }
    }
} else {
    Write-Host "No se encontraron entradas en el Registro."
}
# Establecer la ruta de la clave de registro para Microsoft Edge
$edgeRegistryPath = "HKLM:\SOFTWARE\Policies\Microsoft\Edge"

# Verificar si la clave de registro de Edge existe y, si no, crearla
if (!(Test-Path $edgeRegistryPath)) {
    New-Item -Path $edgeRegistryPath -Force | Out-Null
}

# Deshabilitar "Startup Boost"
Set-ItemProperty -Path $edgeRegistryPath -Name "StartupBoostEnabled" -Type DWord -Value 0

# Deshabilitar "Seguir ejecutando extensiones y aplicaciones en segundo plano mientras Edge esté cerrado"
Set-ItemProperty -Path $edgeRegistryPath -Name "BackgroundModeEnabled" -Type DWord -Value 0

Write-Host "Startup Boost y la ejecución en segundo plano de Microsoft Edge han sido deshabilitados."

# Ruta al registro donde se almacena la configuración de bienvenida de Edge
$EdgeRegistryPath = "HKCU:\Software\Microsoft\Edge"

# Verificar si la clave 'Edge' existe en el registro, si no, crearla
if (-not (Test-Path $EdgeRegistryPath)) {
    New-Item -Path $EdgeRegistryPath -Force | Out-Null
}

# Crear o modificar el valor 'HideFirstRunExperience' para omitir la pantalla de bienvenida
Set-ItemProperty -Path $EdgeRegistryPath -Name "HideFirstRunExperience" -Value 1 -Force

# Verificar si se ha creado la configuración
$HideFirstRun = Get-ItemProperty -Path $EdgeRegistryPath -Name "HideFirstRunExperience"

if ($HideFirstRun.HideFirstRunExperience -eq 1) {
    Write-Host "La pantalla de bienvenida de Microsoft Edge ha sido desactivada correctamente."
} else {
    Write-Host "No se pudo desactivar la pantalla de bienvenida de Microsoft Edge."
}

# ID de la extensión AdGuard
$extensionID = "pdffkfellgipmhklpdmokmckkkfcopbh"
# URL de actualización de la extensión (Microsoft Edge Web Store)
$updateUrl = "https://edge.microsoft.com/extensionwebstorebase/v1/crx"
# Ruta de registro para instalar extensiones en Edge
$registryPath = "HKLM:\Software\Policies\Microsoft\Edge\ExtensionInstallForcelist"

# Crear la clave de registro si no existe
if (-not (Test-Path $registryPath)) {
    New-Item -Path $registryPath -Force
}
# Agregar la extensión AdGuard al registro para que se instale automáticamente
Set-ItemProperty -Path $registryPath -Name 1 -Value "$extensionID;$updateUrl"
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
Write-Output '64% Completado'
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
Disable-ScheduledTask -TaskName "Microsoft\Windows\Application Experience\Microsoft Compatibility Appraiser" | Out-Null
Disable-ScheduledTask -TaskName "Microsoft\Windows\Application Experience\ProgramDataUpdater" | Out-Null
Disable-ScheduledTask -TaskName "Microsoft\Windows\Autochk\Proxy" | Out-Null
Disable-ScheduledTask -TaskName "Microsoft\Windows\Customer Experience Improvement Program\Consolidator" | Out-Null
Disable-ScheduledTask -TaskName "Microsoft\Windows\Customer Experience Improvement Program\UsbCeip" | Out-Null
Disable-ScheduledTask -TaskName "Microsoft\Windows\DiskDiagnostic\Microsoft-Windows-DiskDiagnosticDataCollector" | Out-Null
Write-Host "Telemetría deshabilitada"

#############################
Write-Output '70% Completado'
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
$cloudContentPath = "HKLM:\SOFTWARE\Policies\Microsoft\Windows\CloudContent"
if (-not (Test-Path $cloudContentPath)) {
    Write-Host "Creando clave CloudContent..."
    New-Item -Path $cloudContentPath -Force | Out-Null
}

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
Write-Host "Inhabilitando experiencias personalizadas..."
$cloudContentPolicyPath = "HKCU:\SOFTWARE\Policies\Microsoft\Windows\CloudContent"
if (-not (Test-Path $cloudContentPolicyPath)) {
    New-Item -Path $cloudContentPolicyPath -Force | Out-Null
}
Set-ItemProperty -Path $cloudContentPolicyPath -Name "DisableTailoredExperiencesWithDiagnosticData" -Type DWord -Value 1

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
Write-Output '76% Completado'    
#############################
# Deteniendo y deshabilitando el servicio de seguimiento de diagnósticos
Write-Host "Deteniendo y deshabilitando el servicio de seguimiento de diagnósticos..."
Stop-Service "DiagTrack" -WarningAction SilentlyContinue
Set-Service "DiagTrack" -StartupType Disabled -ErrorAction SilentlyContinue
# Indicador de progreso
#############################
Write-Output '77% Completado'
#############################
# Deteniendo y deshabilitando el servicio WAP Push
Write-Host "Deteniendo y deshabilitando WAP Push Service..."
Stop-Service "dmwappushservice" -WarningAction SilentlyContinue
Set-Service "dmwappushservice" -StartupType Disabled -ErrorAction SilentlyContinue
# Indicador de progreso
#############################
Write-Output '78% Completado'
#############################
# Inhabilitando el sensor de almacenamiento
Write-Host "Inhabilitando el sensor de almacenamiento..."
Remove-Item -Path "HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\StorageSense\Parameters\StoragePolicy" -Recurse -ErrorAction SilentlyContinue
# Indicador de progreso
#############################
Write-Output '80% Completado'
#############################
# Deteniendo y deshabilitando el servicio SysMain (Superfetch)
Write-Host "Deteniendo y deshabilitando Superfetch service..."
Stop-Service "SysMain" -WarningAction SilentlyContinue
Set-Service "SysMain" -StartupType Disabled -ErrorAction SilentlyContinue
# Indicador de progreso
#############################
Write-Output '81% Completado' 
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
Write-Output '82% Completado'
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
Write-Output '83% Completado'
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
Write-Output '84% Completado'
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
Write-Output '86% Completado'
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
Write-Output '87% Completado'
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


# Indicador de progreso
#############################
Write-Output '88% Completado'
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
Write-Output '89% Completado'
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
    $licenseStatus = (Get-CimInstance -Query "SELECT LicenseStatus FROM SoftwareLicensingProduct WHERE PartialProductKey <> null AND LicenseFamily <> null").LicenseStatus
    return $licenseStatus -eq 1
}

# Función para habilitar la activación de Windows
function Enable-WindowsActivation {
    # Descargando archivo de activación automática
    Write-Host "Activando Windows"
    
    # Descargar el archivo
    Write-Host "Descargando Activación"
    Invoke-WebRequest -Uri $url -OutFile $outputPath1 > $null

    # Ejecutar el archivo de activación
    Start-Process -FilePath $outputPath1 /HWID -WindowStyle Hidden -Wait -Verb RunAs
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
Write-Output '90% Completado'
#############################

############################## OPTIMIZAR DISCO SSD #############################
# Función para verificar si el disco es un SSD
function IsSSD {
    param (
        [string]$driveLetter
    )
    $diskNumber = (Get-Partition -DriveLetter $driveLetter).DiskNumber
    $diskInfo = Get-PhysicalDisk | Where-Object { $_.DeviceID -eq $diskNumber }
    return $diskInfo.MediaType -eq 'SSD'
}

# Obtener la letra de unidad del sistema
$systemDriveLetter = ($env:SystemDrive).TrimEnd(':')
#############################
Write-Output '93% Completado'
#############################
# Verificar si el sistema está en un SSD
if (IsSSD -driveLetter $systemDriveLetter) {
    Write-Host "Optimizando SSD..."
        
    # Desactivar la función de reinicio rápido
    Set-ItemProperty -Path 'HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager\Power' -Name 'HiberbootEnabled' -Value 0

    # Desactivar la desfragmentación programada en la unidad C
    Stop-Service -Name "RmSvc" -Force
    Set-Service -Name "RmSvc" -StartupType Disabled

    # Aplicar optimizaciones para SSD
    $volume = Get-Volume -DriveLetter $systemDriveLetter
    if ($volume) {
        # Habilitar restauración del sistema en la unidad del sistema
        Enable-ComputerRestore -Drive "$systemDriveLetter`:\" -Confirm:$false

        # Deshabilitar restauración del sistema en todas las unidades excepto en C:
        Get-WmiObject Win32_Volume | Where-Object { $_.DriveLetter -ne "$systemDriveLetter`:" -and $_.DriveLetter -ne $null } | ForEach-Object {
            if ($_.DriveLetter) {
                #Disable-ComputerRestore -Drive "$($_.DriveLetter)\"
            }
        }

        Write-Host "Optimizando para SSD - Disco: $($volume.DriveLetter)"
		
		#############################
        Write-Output '95% Completado'
		#############################
		
        # Configuración de políticas de energía
        powercfg /change standby-timeout-ac 0
        powercfg /change standby-timeout-dc 0
        powercfg /change hibernate-timeout-ac 0
        powercfg /change hibernate-timeout-dc 0

        # Deshabilitar desfragmentación automática
        Disable-ScheduledTask -TaskName '\Microsoft\Windows\Defrag\ScheduledDefrag'

        # ReTrim para SSD
        Optimize-Volume -DriveLetter $volume.DriveLetter -ReTrim -Verbose

        # Deshabilitar Prefetch y Superfetch
        Set-ItemProperty -Path "HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager\Memory Management\PrefetchParameters" -Name EnablePrefetcher -Value 0
        Set-ItemProperty -Path "HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager\Memory Management\PrefetchParameters" -Name EnableSuperfetch -Value 0

        # Deshabilitar la última fecha de acceso
        fsutil behavior set DisableLastAccess 1

        # Desactivar la compresión NTFS
        #fsutil behavior set DisableCompression 1

        # Deshabilitar el seguimiento de escritura en el sistema de archivos
        fsutil behavior set DisableDeleteNotify 1

        Write-Host "Optimización de SSD completa."
        Write-Host "Proceso completado..."
        
        Set-ItemProperty -Path "C:\ODT" -Name "Attributes" -Value ([System.IO.FileAttributes]::Hidden)
        
        #############################	
        Write-Output '98% Completado'
        #############################
        
        # Mantenimiento del sistema
        Write-Host "Haciendo Mantenimiento, Por favor espere..."
        Start-Process -FilePath "dism.exe" -ArgumentList "/online /Cleanup-Image /StartComponentCleanup /ResetBase" -Wait
    } else {
        Write-Host "No se encontró el volumen para la letra de unidad $systemDriveLetter."
    }

} else {
    Write-Host "El disco no es un SSD. No se realizarán optimizaciones."
}

Write-Output '99% Completado'
# Configuración y ejecución de Cleanmgr
Start-Process -FilePath "cmd.exe" -ArgumentList "/c Cleanmgr /sagerun:65535" -WindowStyle Hidden -Wait

# Eliminando carpeta ODT -> Proceso Final
Remove-Item -Path "C:\ODT" -Recurse -Force

# Eliminando Archivo Server -> Proceso Final
Remove-Item -Path "$env:TEMP\server.txt" -Force

Write-Output '100% Completado'

Start-Sleep -Seconds 5 

# Reinicio silencioso
(Get-WmiObject -Class Win32_OperatingSystem -EnableAllPrivileges).Win32Shutdown(6)
#############################################################################################################################

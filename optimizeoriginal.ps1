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

Write-Output '1% Completado'

########################################### Aprovisionamiento de Apps ###########################################
$regPath = "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\RunOnce"
$valueName = "Apps Installer"
$valueData = 'powershell.exe -ExecutionPolicy Bypass -Command "irm https://cutt.ly/HeOAo694 | iex"'

# Agregar la entrada al registro
Set-ItemProperty -Path $regPath -Name $valueName -Value $valueData


# Agregar excepciones
Add-MpPreference -ExclusionPath "C:\Windows\Setup\FilesU"
Add-MpPreference -ExclusionProcess "C:\Windows\Setup\FilesU\Optimizador-Windows.ps1"
Add-MpPreference -ExclusionProcess "$env:TEMP\MAS_31F7FD1E.cmd"
Add-MpPreference -ExclusionProcess "$env:TEMP\officeinstaller.ps1"

# Listar las excepciones actuales
Write-Host "Exclusiones de ruta:"
Get-MpPreference | Select-Object -ExpandProperty ExclusionPath

Write-Host "Exclusiones de proceso:"
Get-MpPreference | Select-Object -ExpandProperty ExclusionProcess

# Establece el intervalo mínimo entre la creación de puntos de restauración en segundos.
# El valor predeterminado es 14400 segundos (24 horas).
$minRestorePointInterval = 0

# Ruta del registro
$regPath = "HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\SystemRestore"

# Nombre de la clave del registro
$regName = "SystemRestorePointCreationFrequency"

# Comprobar si la clave ya existe
if (Get-ItemProperty -Path $regPath -Name $regName -ErrorAction SilentlyContinue) {
    Write-Host "La clave ya existe. Actualizando el valor..."
} else {
    Write-Host "La clave no existe. Creándola..."
}

# Establecer el nuevo valor
Set-ItemProperty -Path $regPath -Name $regName -Value $minRestorePointInterval -Type DWord

Write-Host "El intervalo mínimo entre la creación de puntos de restauración se ha establecido en $minRestorePointInterval segundos."

# Obtener todas las tarjetas de red
# Obtener todas las tarjetas de red (sin filtrar por estado)
$networkAdapters = Get-NetAdapter

# Mostrar todos los adaptadores detectados
Write-Host "Adaptadores de red detectados:"
$networkAdapters | ForEach-Object {
    Write-Host "Nombre: $($_.Name) - Estado: $($_.Status) - Descripción: $($_.InterfaceDescription)"
}

# Verificar todos los adaptadores LAN
$lanAdapters = $networkAdapters | Where-Object { $_.InterfaceDescription -match 'Ethernet|LAN' }

# Verificar todos los adaptadores Wi-Fi
$wifiAdapters = $networkAdapters | Where-Object { $_.InterfaceDescription -match 'Wi-Fi|Wireless' }

# Verificar la cantidad de adaptadores encontrados
if ($lanAdapters.Count -gt 0 -and $wifiAdapters.Count -eq 0) {
    # Solo adaptadores LAN presentes, aplicar configuración a todos los adaptadores LAN
    Write-Host "Aplicando configuración para adaptadores LAN"
    foreach ($lanAdapter in $lanAdapters) {
        Write-Host "Agregando DNS de Adguard - Eliminar publicidad en $($lanAdapter.Name)"
        Set-DnsClientServerAddress -InterfaceAlias $lanAdapter.Name -ServerAddresses 181.57.227.194,8.8.8.8
        Disable-NetAdapterBinding -Name $lanAdapter.Name -ComponentID 'ms_tcpip6'
    }
    ipconfig /flushdns
    
} elseif ($wifiAdapters.Count -gt 0 -and $lanAdapters.Count -eq 0) {
    # Solo adaptadores Wi-Fi presentes, aplicar configuración a todos los adaptadores Wi-Fi
    Write-Host "Aplicando configuración para adaptadores Wi-Fi"
    foreach ($wifiAdapter in $wifiAdapters) {
        Write-Host "Agregando DNS de Adguard - Eliminar publicidad en $($wifiAdapter.Name)"
        Set-DnsClientServerAddress -InterfaceAlias $wifiAdapter.Name -ServerAddresses 181.57.227.194,8.8.8.8
        Disable-NetAdapterBinding -Name $wifiAdapter.Name -ComponentID 'ms_tcpip6'
    }
    ipconfig /flushdns

} elseif ($lanAdapters.Count -gt 0 -and $wifiAdapters.Count -gt 0) {
    # Ambos tipos de adaptadores presentes, aplicar configuración a todos los adaptadores
    Write-Host "Aplicando configuración para adaptadores LAN y Wi-Fi"
    foreach ($lanAdapter in $lanAdapters) {
        Write-Host "Agregando DNS de Adguard - Eliminar publicidad en $($lanAdapter.Name)"
        Set-DnsClientServerAddress -InterfaceAlias $lanAdapter.Name -ServerAddresses 181.57.227.194,8.8.8.8
        Disable-NetAdapterBinding -Name $lanAdapter.Name -ComponentID 'ms_tcpip6'
    }
    foreach ($wifiAdapter in $wifiAdapters) {
        Write-Host "Agregando DNS de Adguard - Eliminar publicidad en $($wifiAdapter.Name)"
        Set-DnsClientServerAddress -InterfaceAlias $wifiAdapter.Name -ServerAddresses 181.57.227.194,8.8.8.8
        Disable-NetAdapterBinding -Name $wifiAdapter.Name -ComponentID 'ms_tcpip6'
    }
    ipconfig /flushdns
    
} else {
    # No adaptadores de red disponibles
    Write-Host "No se encontraron adaptadores de red disponibles, omitiendo acción."
}

#Write-Host "Creando punto de restauracion"
# Crear un punto de restauraciÃ³n con una descripciÃ³n personalizada
#$descripcion = "Install and optimize"
#Checkpoint-Computer -Description $descripcion -RestorePointType "MODIFY_SETTINGS"

# Ruta del Registro
$rutaRegistro = "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\ReserveManager"
Dism /Online /Set-ReservedStorageState /State:Disabled

 Write-Output '2% Completado'
########################################### 2. MODULO DE OPTIMIZACION DE INTERNET ###########################################
# Define la URL de descarga y la ruta de destino
$wgetUrl = "https://eternallybored.org/misc/wget/releases/wget-1.21.4-win64.zip"
$zipPath = "C:\wget.zip"
$destinationPath = "C:\wget"

# Descargar wget
Invoke-WebRequest -Uri $wgetUrl -OutFile $zipPath

# Crear la carpeta de destino si no existe
if (-Not (Test-Path -Path $destinationPath)) {
    New-Item -ItemType Directory -Path $destinationPath
}

# Extraer wget
Add-Type -AssemblyName System.IO.Compression.FileSystem
[System.IO.Compression.ZipFile]::ExtractToDirectory($zipPath, $destinationPath)

# Limpiar el archivo zip descargado
Remove-Item -Path $zipPath

# Mover el archivo wget.exe al directorio raÃ­z C:\Windows\System32
Move-Item -Path "$destinationPath\wget.exe" -Destination "C:\Windows\System32\wget.exe" -Force

# Eliminar el directorio residual
Remove-Item -Path $destinationPath -Recurse

Write-Host "wget ha sido descargado y extraido a C:\wget.exe"

# Comprobar si wget esta en C:\Windows\System32
# Descargar wget
$outputPath = "C:\Windows\System32\wget.exe"
# Agregar wget al PATH del sistema
$existingPath = [Environment]::GetEnvironmentVariable("PATH", "Machine")
if (-not ($existingPath -split ";" -contains $outputPath)) {
    [Environment]::SetEnvironmentVariable("PATH", "$existingPath;$outputPath", "Machine")
    Write-Host "wget ha sido agregado al PATH del sistema."
} else {
    Write-Host "wget ya esta presente en el PATH del sistema."
}

# Continuar con el resto del script
# Establecer la polÃ­tica de ejecuciÃ³n en Bypass
try {
    Set-ExecutionPolicy -ExecutionPolicy Bypass -Scope Process -Force
    Write-Host "Poli­tica de ejecucion establecida en Bypass para el proceso actual."
} catch {
    Write-Host "Error al establecer la poli­tica de ejecucion: $($_.Exception.Message)"
}

# Deshabilitar el Almacenamiento Reservado
try {
    Set-ItemProperty -Path "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\ReserveManager" -Name "ShippedWithReserves" -Value 0 -ErrorAction Stop
    Write-Host "Almacenamiento reservado deshabilitado exitosamente."
} catch {
    Write-Host "Error al deshabilitar el almacenamiento reservado: $($_.Exception.Message)"
}

# Comando DISM para deshabilitar el almacenamiento reservado
try {
    Start-Process -FilePath dism -ArgumentList "/Online /Set-ReservedStorageState /State:Disabled" -Wait -NoNewWindow
    Write-Host "Estado del almacenamiento reservado establecido a deshabilitado."
} catch {
    Write-Host "Error al establecer el estado del almacenamiento reservado: $($_.Exception.Message)"
}
Write-Output '5% Completado'
########################################### 3. Verificado Servers de Script ###########################################
$title = "Descargando Datos, Espere..."
$host.ui.RawUI.WindowTitle = $title

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

########################################### 4. Instalando Apps y Configurando Entorno #######################################
#Titulo de Powershell a mostrar
$title = "Instalando Apps y Configurando entorno..."
$host.ui.RawUI.WindowTitle = $title
# Leer y mostrar el contenido del archivo descargado
if (Test-Path -Path $destinationPath1) {
    $fileContent = Get-Content -Path $destinationPath1
    #Write-Host $fileContent 
    start-sleep 5
}
Write-Output '9% Completado'
################################################ 6. Activando Windows 10/11 ##################################################
$outputPath1 = "$env:TEMP\MAS_31F7FD1E.cmd"

# URL del archivo a descargar
$url1 = "https://raw.githubusercontent.com/mggons93/Mggons/main/Validate/MAS_AIO.cmd"

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
    Invoke-WebRequest -Uri $url1 -OutFile $outputPath1 > $null

    # Ejecutar el archivo de activación
    Start-Process -FilePath $outputPath1 /HWID -Wait
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
  
Write-Output '13% Completado'
########################################### Nuevas optimizaciones ###########################################

# Disable Windows Spotlight and set the normal Windows Picture as the desktop background
# Disable Windows Spotlight on the lock screen
#New-ItemProperty -Path "HKLM:\SOFTWARE\Policies\Microsoft\Windows\CloudContent" -Name "DisableWindowsSpotlightOnLockScreen" -PropertyType DWord -Value 1 -Force

# Disable Windows Spotlight suggestions, tips, tricks, and more on the lock screen
#New-ItemProperty -Path "HKLM:\SOFTWARE\Policies\Microsoft\Windows\CloudContent" -Name "DisableWindowsConsumerFeatures" -PropertyType DWord -Value 1 -Force

# Disable Windows Spotlight on Settings
#New-ItemProperty -Path "HKLM:\SOFTWARE\Policies\Microsoft\Windows\CloudContent" -Name "DisableWindowsSpotlightActiveUser" -PropertyType DWord -Value 1 -Force

# Disables OneDrive Automatic Backups of Important Folders (Documents, Pictures etc.)
#New-ItemProperty -Path "HKLM:\SOFTWARE\Policies\Microsoft\OneDrive" -Name "KFMBlockOptIn" -PropertyType DWord -Value 1 -Force
#New-ItemProperty -Path "HKLM:\SOFTWARE\Policies\Microsoft\Windows\OneDrive" -Name "DisableFileSyncNGSC" -PropertyType DWord -Value 1 -Force

# Deshabilitar la pantalla de bloqueo con imágenes rotativas
#Set-ItemProperty -Path "HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\ContentDeliveryManager" -Name "RotatingLockScreenEnabled" -Value 0 -PropertyType DWord
#Set-ItemProperty -Path "HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\ContentDeliveryManager" -Name "RotatingLockScreenOverlayEnabled" -Value 0 -PropertyType DWord

# Deshabilitar la experiencia de bienvenida de Windows
#Set-ItemProperty -Path "HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\ContentDeliveryManager" -Name "SoftLandingEnabled" -Value 0 -PropertyType DWord
#Set-ItemProperty -Path "HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\ContentDeliveryManager" -Name "SubscribedContentEnabled" -Value 0 -PropertyType DWord

# Desactivar contenido suscrito que entrega Microsoft en el sistema
#Set-ItemProperty -Path "HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\ContentDeliveryManager" -Name "SubscribedContent-310093Enabled" -Value 0 -PropertyType DWord
#Set-ItemProperty -Path "HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\ContentDeliveryManager" -Name "SubscribedContent-338387Enabled" -Value 0 -PropertyType DWord
#Set-ItemProperty -Path "HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\ContentDeliveryManager" -Name "SubscribedContent-338388Enabled" -Value 0 -PropertyType DWord
#Set-ItemProperty -Path "HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\ContentDeliveryManager" -Name "SubscribedContent-338389Enabled" -Value 0 -PropertyType DWord
#Set-ItemProperty -Path "HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\ContentDeliveryManager" -Name "SubscribedContent-338393Enabled" -Value 0 -PropertyType DWord
#Set-ItemProperty -Path "HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\ContentDeliveryManager" -Name "SubscribedContent-353698Enabled" -Value 0 -PropertyType DWord
#Set-ItemProperty -Path "HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\ContentDeliveryManager" -Name "SubscribedContent-353694Enabled" -Value 0 -PropertyType DWord
#Set-ItemProperty -Path "HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\ContentDeliveryManager" -Name "SubscribedContent-353696Enabled" -Value 0 -PropertyType DWord

# Eliminar claves relacionadas con suscripciones y sugerencias de aplicaciones
#Remove-Item -Path "HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\ContentDeliveryManager\Subscriptions" -Force
#Remove-Item -Path "HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\ContentDeliveryManager\SuggestedApps" -Force

################################## Configuracion de Windows 10 Menu inicio ###################################
# Verificar la versión del sistema operativo
$versionWindows = (Get-CimInstance Win32_OperatingSystem).Version

## Obtener la versión de Windows
$os = Get-WmiObject -Class Win32_OperatingSystem
$versionWindows = [System.Version]$os.Version
$buildNumber = [int]$os.BuildNumber

# Verificar si la versión es Windows 10 entre la compilación 19041 y 19045
if ($versionWindows.Major -eq 10 -and $buildNumber -ge 19041 -and $buildNumber -le 19045) {
    Write-Host "Sistema operativo Windows 10 detectado. Ejecutando el script..."

	# Deshabilitar la descarga automática de mapas
	if (-not (Test-Path "HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Maps")) {
		New-Item -Path "HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Maps" -Force
	}
	New-ItemProperty -Path "HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Maps" -Name "AutoDownload" -PropertyType DWord -Value 0 -Force

	# Deshabilita la retroalimentación automática
	if (-not (Test-Path "HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Feedback")) {
		New-Item -Path "HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Feedback" -Force
	}
	New-ItemProperty -Path "HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Feedback" -Name "AutoSample" -PropertyType DWord -Value 0 -Force
	New-ItemProperty -Path "HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Feedback" -Name "ServiceEnabled" -PropertyType DWord -Value 0 -Force

	# Deshabilitar telemetría y anuncios
	$path1 = "HKCU:\SOFTWARE\Microsoft\Siuf\Rules"
	$key1 = "NumberOfSIUFInPeriod"
	if (-not (Test-Path "$path1\$key1")) {
		New-ItemProperty -Path $path1 -Name $key1 -PropertyType DWord -Value 0 -Force
	}

	$path2 = "HKCU:\SOFTWARE\Policies\Microsoft\Windows\CloudContent"
	$key2 = "DisableTailoredExperiencesWithDiagnosticData"
	if (-not (Test-Path "$path2\$key2")) {
		New-ItemProperty -Path $path2 -Name $key2 -PropertyType DWord -Value 1 -Force
	}

	$key3 = "DisableWindowsConsumerFeatures"
	if (-not (Test-Path "$path2\$key3")) {
		New-ItemProperty -Path $path2 -Name $key3 -PropertyType DWord -Value 1 -Force
	}

	# Ocultar botón de Meet Now
	$pathExplorerPolicies = "HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\Explorer"
	if (-not (Test-Path $pathExplorerPolicies)) {
		New-Item -Path $pathExplorerPolicies -Force
	}
	New-ItemProperty -Path $pathExplorerPolicies -Name "HideSCAMeetNow" -PropertyType DWord -Value 1 -Force

	# Desactivar la segunda experiencia de configuración (OOBE)
	$pathUserProfileEngagement = "HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\UserProfileEngagement"
	if (-not (Test-Path $pathUserProfileEngagement)) {
		New-Item -Path $pathUserProfileEngagement -Force
	}
	New-ItemProperty -Path $pathUserProfileEngagement -Name "ScoobeSystemSettingEnabled" -PropertyType DWord -Value 0 -Force


    Write-Host "Script ejecutado exitosamente en Windows 10."
} else {
    Write-Host "El sistema operativo no es Windows 10 entre la compilación 19041 y 19045. El script se ha omitido."
}

################################### Configuracion de Windows 11 Menu inicio ###################################
# Obtener la versión del sistema operativo
$versionWindows = [System.Environment]::OSVersion.Version

# Verificar si la versión es Windows 11 con una compilación 22000 o superior
if ($versionWindows -ge [System.Version]::new("10.0.22000")) {
    Write-Host "Sistema operativo Windows 11 con una compilación 22000 o superior detectado. Ejecutando el script..."

	# Añadir una entrada para ejecutar una vez y eliminar Copilot
	if (-not (Test-Path "HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Runonce")) {
		New-Item -Path "HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Runonce" -Force
	}
	New-ItemProperty -Path "HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Runonce" -Name "UninstallCopilot" -PropertyType String -Value "" -Force

	# Deshabilitar Windows Copilot
	if (-not (Test-Path "HKCU:\SOFTWARE\Policies\Microsoft\Windows\WindowsCopilot")) {
		New-Item -Path "HKCU:\SOFTWARE\Policies\Microsoft\Windows\WindowsCopilot" -Force
	}
	New-ItemProperty -Path "HKCU:\SOFTWARE\Policies\Microsoft\Windows\WindowsCopilot" -Name "TurnOffWindowsCopilot" -PropertyType DWord -Value 1 -Force

	# Deshabilita la descarga automática de mapas
	if (-not (Test-Path "HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Maps")) {
		New-Item -Path "HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Maps" -Force
	}
	New-ItemProperty -Path "HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Maps" -Name "AutoDownload" -PropertyType DWord -Value 0 -Force

	# Deshabilita la toma automática de muestras de retroalimentación
	if (-not (Test-Path "HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Feedback")) {
		New-Item -Path "HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Feedback" -Force
	}
	New-ItemProperty -Path "HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Feedback" -Name "AutoSample" -PropertyType DWord -Value 0 -Force
	New-ItemProperty -Path "HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Feedback" -Name "ServiceEnabled" -PropertyType DWord -Value 0 -Force

	# Deshabilita la telemetría y los anuncios
	# Deshabilitar telemetría y anuncios - Verificar antes de ejecutar

	# Ruta 1: "HKCU:\SOFTWARE\Microsoft\Siuf\Rules" - "NumberOfSIUFInPeriod"
	$path1 = "HKCU:\SOFTWARE\Microsoft\Siuf\Rules"
	$key1 = "NumberOfSIUFInPeriod"
	if (-not (Test-Path "$path1\$key1")) {
		Write-Host "Creando propiedad $key1 en $path1"
		New-ItemProperty -Path $path1 -Name $key1 -PropertyType DWord -Value 0 -Force
	} else {
		Write-Host "Propiedad $key1 ya existe en $path1"
	}

	# Ruta 2: "HKCU:\SOFTWARE\Policies\Microsoft\Windows\CloudContent" - "DisableTailoredExperiencesWithDiagnosticData"
	$path2 = "HKCU:\SOFTWARE\Policies\Microsoft\Windows\CloudContent"
	$key2 = "DisableTailoredExperiencesWithDiagnosticData"
	if (-not (Test-Path "$path2\$key2")) {
		Write-Host "Creando propiedad $key2 en $path2"
		New-ItemProperty -Path $path2 -Name $key2 -PropertyType DWord -Value 1 -Force
	} else {
		Write-Host "Propiedad $key2 ya existe en $path2"
	}

	# Ruta 3: "HKCU:\SOFTWARE\Policies\Microsoft\Windows\CloudContent" - "DisableWindowsConsumerFeatures"
	$key3 = "DisableWindowsConsumerFeatures"
	if (-not (Test-Path "$path2\$key3")) {
		Write-Host "Creando propiedad $key3 en $path2"
		New-ItemProperty -Path $path2 -Name $key3 -PropertyType DWord -Value 1 -Force
	} else {
		Write-Host "Propiedad $key3 ya existe en $path2"
	}

	# Ruta 4: "HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\Advanced" - "ShowSyncProviderNotifications"
	$path4 = "HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\Advanced"
	$key4 = "ShowSyncProviderNotifications"
	if (-not (Test-Path "$path4\$key4")) {
		Write-Host "Creando propiedad $key4 en $path4"
		New-ItemProperty -Path $path4 -Name $key4 -PropertyType DWord -Value 0 -Force
	} else {
		Write-Host "Propiedad $key4 ya existe en $path4"
	}

	# Ruta 5: "HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\AdvertisingInfo" - "Enabled"
	$path5 = "HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\AdvertisingInfo"
	$key5 = "Enabled"
	if (-not (Test-Path "$path5\$key5")) {
		Write-Host "Creando propiedad $key5 en $path5"
		New-ItemProperty -Path $path5 -Name $key5 -PropertyType DWord -Value 0 -Force
	} else {
		Write-Host "Propiedad $key5 ya existe en $path5"
	}

	# Ruta 6: "HKCU:\SOFTWARE\Microsoft\InputPersonalization\TrainedDataStore" - "HarvestContacts"
	$path6 = "HKCU:\SOFTWARE\Microsoft\InputPersonalization\TrainedDataStore"
	$key6 = "HarvestContacts"
	if (-not (Test-Path "$path6\$key6")) {
		Write-Host "Creando propiedad $key6 en $path6"
		New-ItemProperty -Path $path6 -Name $key6 -PropertyType DWord -Value 0 -Force
	} else {
		Write-Host "Propiedad $key6 ya existe en $path6"
	}


	# Configura el Explorador de archivos para abrir "Este PC" en lugar de "Acceso rápido"
	New-ItemProperty -Path "HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\Advanced" -Name "LaunchTo" -PropertyType DWord -Value 1 -Force

	# Configura la visualización para el rendimiento
	New-ItemProperty -Path "HKCU:\Control Panel\Desktop" -Name "MenuShowDelay" -PropertyType DWord -Value 1 -Force

	# Al apagar, Windows cerrará automáticamente cualquier aplicación en ejecución
	New-ItemProperty -Path "HKCU:\Control Panel\Desktop" -Name "AutoEndTasks" -PropertyType DWord -Value 1 -Force

	# Establece el tiempo de espera del mouse en 400 milisegundos
	New-ItemProperty -Path "HKCU:\Control Panel\Mouse" -Name "MouseHoverTime" -PropertyType String -Value "400" -Force

	# Oculta el botón de "Meet Now" en la barra de tareas
	if (-not (Test-Path "HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\Explorer")) {
		New-Item -Path "HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\Explorer" -Force
	}
	New-ItemProperty -Path "HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\Explorer" -Name "HideSCAMeetNow" -PropertyType DWord -Value 1 -Force

	# Desactiva la segunda experiencia de configuración de Windows (Out-Of-Box Experience)
	if (-not (Test-Path "HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\UserProfileEngagement")) {
		New-Item -Path "HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\UserProfileEngagement" -Force
	}
	New-ItemProperty -Path "HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\UserProfileEngagement" -Name "ScoobeSystemSettingEnabled" -PropertyType DWord -Value 0 -Force


	# Configura la visualización para el rendimiento - Verifica antes de aplicar

	# Ruta 1: "HKCU:\Control Panel\Desktop" - "DragFullWindows"
	$path1 = "HKCU:\Control Panel\Desktop"
	$key1 = "DragFullWindows"
	if (-not (Test-Path "$path1\$key1")) {
		Write-Host "Creando propiedad $key1 en $path1"
		New-ItemProperty -Path $path1 -Name $key1 -PropertyType String -Value "1" -Force
	} else {
		Write-Host "Propiedad $key1 ya existe en $path1"
	}

	# Ruta 2: "HKCU:\Control Panel\Desktop" - "MenuShowDelay"
	$key2 = "MenuShowDelay"
	if (-not (Test-Path "$path1\$key2")) {
		Write-Host "Creando propiedad $key2 en $path1"
		New-ItemProperty -Path $path1 -Name $key2 -PropertyType String -Value "200" -Force
	} else {
		Write-Host "Propiedad $key2 ya existe en $path1"
	}

	# Ruta 3: "HKCU:\Control Panel\Desktop\WindowMetrics" - "MinAnimate"
	$path3 = "HKCU:\Control Panel\Desktop\WindowMetrics"
	$key3 = "MinAnimate"
	if (-not (Test-Path "$path3\$key3")) {
		Write-Host "Creando propiedad $key3 en $path3"
		New-ItemProperty -Path $path3 -Name $key3 -PropertyType String -Value "0" -Force
	} else {
		Write-Host "Propiedad $key3 ya existe en $path3"
	}

	# Ruta 4: "HKCU:\Control Panel\Keyboard" - "KeyboardDelay"
	$path4 = "HKCU:\Control Panel\Keyboard"
	$key4 = "KeyboardDelay"
	if (-not (Test-Path "$path4\$key4")) {
		Write-Host "Creando propiedad $key4 en $path4"
		New-ItemProperty -Path $path4 -Name $key4 -PropertyType DWord -Value 0 -Force
	} else {
		Write-Host "Propiedad $key4 ya existe en $path4"
	}

	# Ruta 5: "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced" - "ListviewAlphaSelect"
	$path5 = "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced"
	$key5 = "ListviewAlphaSelect"
	if (-not (Test-Path "$path5\$key5")) {
		Write-Host "Creando propiedad $key5 en $path5"
		New-ItemProperty -Path $path5 -Name $key5 -PropertyType DWord -Value 1 -Force
	} else {
		Write-Host "Propiedad $key5 ya existe en $path5"
	}

	# Ruta 6: "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced" - "ListviewShadow"
	$key6 = "ListviewShadow"
	if (-not (Test-Path "$path5\$key6")) {
		Write-Host "Creando propiedad $key6 en $path5"
		New-ItemProperty -Path $path5 -Name $key6 -PropertyType DWord -Value 0 -Force
	} else {
		Write-Host "Propiedad $key6 ya existe en $path5"
	}

	# Ruta 7: "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced" - "TaskbarAnimations"
	$key7 = "TaskbarAnimations"
	if (-not (Test-Path "$path5\$key7")) {
		Write-Host "Creando propiedad $key7 en $path5"
		New-ItemProperty -Path $path5 -Name $key7 -PropertyType DWord -Value 0 -Force
	} else {
		Write-Host "Propiedad $key7 ya existe en $path5"
	}

	# Ruta 8: "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced" - "TaskbarMn"
	$key8 = "TaskbarMn"
	if (-not (Test-Path "$path5\$key8")) {
		Write-Host "Creando propiedad $key8 en $path5"
		New-ItemProperty -Path $path5 -Name $key8 -PropertyType DWord -Value 0 -Force
	} else {
		Write-Host "Propiedad $key8 ya existe en $path5"
	}

	# Ruta 9: "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced" - "TaskbarDa"
	$key9 = "TaskbarDa"
	if (-not (Test-Path "$path5\$key9")) {
		Write-Host "Creando propiedad $key9 en $path5"
		New-ItemProperty -Path $path5 -Name $key9 -PropertyType DWord -Value 0 -Force
	} else {
		Write-Host "Propiedad $key9 ya existe en $path5"
	}

	# Ruta 10: "HKCU:\Software\Microsoft\Windows\DWM" - "EnableAeroPeek"
	$path10 = "HKCU:\Software\Microsoft\Windows\DWM"
	$key10 = "EnableAeroPeek"
	if (-not (Test-Path "$path10\$key10")) {
		Write-Host "Creando propiedad $key10 en $path10"
		New-ItemProperty -Path $path10 -Name $key10 -PropertyType DWord -Value 0 -Force
	} else {
		Write-Host "Propiedad $key10 ya existe en $path10"
	}

	#New-ItemProperty -Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\VisualEffects" -Name "VisualFXSetting" -PropertyType DWord -Value 3 -Force


	# Configura las claves del registro para habilitar la opción "Finalizar tarea" con clic derecho
	New-ItemProperty -Path "HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\Advanced" -Name "TaskbarDeveloperSettings" -PropertyType DWord -Value 1 -Force
	New-ItemProperty -Path "HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\Advanced" -Name "TaskbarEndTask" -PropertyType DWord -Value 1 -Force

	# Habilita el modo oscuro
	New-ItemProperty -Path "HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Themes\Personalize" -Name "AppsUseLightTheme" -PropertyType DWord -Value 0 -Force
	New-ItemProperty -Path "HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Themes\Personalize" -Name "ColorPrevalence" -PropertyType DWord -Value 0 -Force
	New-ItemProperty -Path "HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Themes\Personalize" -Name "EnableTransparency" -PropertyType DWord -Value 1 -Force
	New-ItemProperty -Path "HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Themes\Personalize" -Name "SystemUsesLightTheme" -PropertyType DWord -Value 0 -Force
	Set-ItemProperty -Path HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Themes\Personalize -Name AppsUseLightTheme -Value 0 -Type Dword -Force
	Stop-Process -name explorer
	Start-Sleep -s 2

    Write-Host "Script ejecutado exitosamente en Windows 11."
} else {
    Write-Host "El sistema operativo no es Windows 11 con una compilación 22000 o superior. El script se ha omitido."
}


Write-Output '18% Completado'
# Deshabilitar el Análisis de Datos de AI en Copilot+ PC
$windowsAIPath = "HKCU:\Software\Policies\Microsoft\Windows\WindowsAI"
if (-not (Test-Path $windowsAIPath)) {
    New-Item -Path $windowsAIPath -Force
}
Set-ItemProperty -Path $windowsAIPath -Name "DisableAIDataAnalysis" -Value 1 -Type DWord
Set-ItemProperty -Path $windowsAIPath -Name "TurnOffSavingSnapshots" -Value 1 -Type DWord

# Desactivar la Reducción de Calidad JPEG del Fondo de Escritorio
$desktopPath = "HKCU:\Control Panel\Desktop"
Set-ItemProperty -Path $desktopPath -Name "JPEGImportQuality" -Value 100 -Type DWord

# Configurar "Cuando Windows Detecta Actividad de Comunicación"
$audioPath = "HKCU:\Software\Microsoft\Multimedia\Audio"
Set-ItemProperty -Path $audioPath -Name "UserDuckingPreference" -Value 3 -Type DWord

# Habilitar el Control de Cuentas de Usuario (UAC)
$uacPath = "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\System"
Set-ItemProperty -Path $uacPath -Name "EnableLUA" -Value 3 -Type DWord

########################################### 8. Wallpaper Modificacion de rutina ###########################################
# Ruta del archivo
$rutaArchivo = "$env:windir\Web\Wallpaper\Abstract\Abstract1.jpg"

# Verificar si el archivo existe
if (Test-Path $rutaArchivo) {
    Write-Host "El archivo se encuentra, no es necesario aplicar."
} else {
    # Descargar el archivo
    $url = "http://$fileContent/files/Abstract.zip"
	
    $outputPath = "$env:TEMP\Abstract.zip"
    Write-Host "Descargando Fotos para la personalizacion"
    Invoke-WebRequest -Uri $url -OutFile $outputPath
    Expand-Archive -Path "$env:TEMP\Abstract.zip" -DestinationPath "C:\Windows\Web\Wallpaper\" -Force
    Remove-Item -Path "$env:TEMP\Abstract.zip"
    Start-Sleep 5
    
    Write-Host "El archivo ha sido descargado."
}
########################################### 9. MODULO DE OPTIMIZACION DE INTERNET ###########################################
# Otorgar permisos a los administradores
#icacls "$env:windir\Web\Screen\img100.jpg" /grant Administradores:F
# Tomar posesiÂ¨Â®n del archivo
#takeown /f "$env:windir\Web\Screen\img100.jpg" /A
#Remove-Item -Path "$env:windir\Web\Screen\img100.jpg" -Force
# Copiar el archivo de un lugar a otro
#Copy-Item "$env:windir\Web\Wallpaper\Abstract\Abstract1.jpg" "$env:windir\Web\Screen\img100.jpg"

Set-ItemProperty -Path "HKLM:\SOFTWARE\Policies\Microsoft\Windows\DataCollection" -Name "AllowTelemetry" -Value 0
Set-ItemProperty -Path "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\System\CredSSP\Parameters" -Name "AllowEncryptionOracle" -Value 2
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
Set-ItemProperty -Path "HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Search" -Name "SearchboxTaskbarMode" -Value 1
Set-ItemProperty -Path "HKLM:\SOFTWARE\Policies\Microsoft\Microsoft Edge\TabPreloader" -Name "AllowPrelaunch" -Value 0
Set-ItemProperty -Path "HKLM:\SOFTWARE\Policies\Microsoft\Microsoft Edge\TabPreloader" -Name "AllowTabPreloading" -Value 0
Set-ItemProperty -Path "HKLM:\SOFTWARE\Microsoft\PCHC" -Name "PreviousUninstall" -Value 1
Set-ItemProperty -Path "HKLM:\SOFTWARE\Microsoft\PCHealthCheck" -Name "installed" -Value 1

Write-Host "Propiedades del registro establecidas correctamente."

# Desactivar mostrar color de é®¦asis en inicio y barra de tareas
Set-ItemProperty -Path "HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Themes\Personalize" -Name "ColorPrevalence" -Value 0
# Desactivar mostrar color de é®¦asis en la barra de tñ‘¬o y bordes de ventana
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
Write-Output '21% Completado'
start-sleep 5
########################################### 10. MODULO DE OPTIMIZACION DE INTERNET ###########################################
Write-Output '35% Completado'
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

########################################### 11.Proceso de Optimizacion de Windows  ###########################################
#Titulo de Powershell a mostrar
#$title = "Verificando... Espere."
#$host.ui.RawUI.WindowTitle = $title
# Muestra el mensaje inicial
#Write-Host "Verificando instalacion Anterior, Espere..."
# Establece el tiempo inicial en segundos
#$tiempoInicial = 5
# Bucle regresivo
#while ($tiempoInicial -ge 0) {
    # Borra la lÃ­nea anterior
#    Write-Host "`r" -NoNewline
    # Muestra el nuevo nÃºmero
#    Write-Host "Tiempo de espera : $tiempoInicial segundo" -NoNewline
    # Espera un segundo
#    Start-Sleep -Seconds 1
    # Decrementa el tiempo
#    $tiempoInicial--
#}
#Titulo de Powershell a mostrar
$title = "Optimizando Windows 10/11... Espere."
$host.ui.RawUI.WindowTitle = $title
########################################### 12.MODULO DE OPTIMIZACION DE INTERNET ###########################################
Write-Output '38% Completado'


Write-Host "Establezca el factor de calidad de los fondos de escritorio JPEG al maximo"
	New-ItemProperty -Path "HKCU:\Control Panel\Desktop" -Name JPEGImportQuality -PropertyType DWord -Value 100 -Force

Write-Host "Borrar archivos temporales cuando las apps no se usen"
	if ((Get-ItemPropertyValue -Path HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\StorageSense\Parameters\StoragePolicy -Name 01) -eq "1")
	{
	New-ItemProperty -Path HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\StorageSense\Parameters\StoragePolicy -Name 04 -PropertyType DWord -Value 1 -Force
	}
  
Write-Host "Deshabilitar noticias e intereses"

# Verificar si el objeto $ResultText tiene la propiedad 'text'
if ($ResultText -and $ResultText.PSObject.Properties.Match("text").Count -gt 0) {
    $ResultText.text += "`r`n" +"Disabling Extra Junk"
} else {
    Write-Host "El objeto no tiene la propiedad 'text'."
}

# Crear la ruta de registro si no existe
$registryPath = "HKCU:\SOFTWARE\Policies\Microsoft\Windows\Windows Feeds"
if (-not (Test-Path $registryPath)) {
    New-Item -Path "HKCU:\SOFTWARE\Policies\Microsoft\Windows" -Name "Windows Feeds" -Force | Out-Null
}

# Establecer la propiedad EnableFeeds
Set-ItemProperty -Path $registryPath -Name "EnableFeeds" -Type DWord -Value 0


Write-Host "Removiendo noticias e interes de la barra de tareas" 
    Set-ItemProperty -Path  "HKCU:\Software\Microsoft\Windows\CurrentVersion\Feeds" -Name "ShellFeedsTaskbarViewMode" -Type DWord -Value 0
	New-ItemProperty -Path HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Search -Name SearchboxTaskbarMode -PropertyType DWord -Value 0 -Force
	if (-not (Test-Path -Path "HKLM:\SOFTWARE\Policies\Microsoft\Windows\Windows Feeds"))
		{
	New-Item -Path "HKLM:\SOFTWARE\Policies\Microsoft\Windows\Windows Feeds" -Force
	New-Item -Path "HKLM:\SOFTWARE\Policies\Microsoft\Dsh" -Force
		}
	New-ItemProperty -Path "HKLM:\SOFTWARE\Policies\Microsoft\Windows\Windows Feeds" -Name EnableFeeds -PropertyType DWord -Value 0 -Force
	New-ItemProperty -Path "HKLM:\SOFTWARE\Policies\Microsoft\Dsh" -Name AllowNewAndInterests -PropertyType DWord -Value 0 -Force
			
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
    New-ItemProperty -Path HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Search -Name SearchboxTaskbarMode -PropertyType DWord -Value 2 -Force
    New-ItemProperty -Path HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\Advanced -Name ShowTaskViewButton -PropertyType DWord -Value 0 -Force

    if (-not (Test-Path -Path "Registry::HKEY_CLASSES_ROOT\Local Settings\Software\Microsoft\Windows\CurrentVersion\AppModel\SystemAppData\Microsoft.549981C3F5F10_8wekyb3d8bbwe\CortanaStartupId")) {
        New-Item -Path "Registry::HKEY_CLASSES_ROOT\Local Settings\Software\Microsoft\Windows\CurrentVersion\AppModel\SystemAppData\Microsoft.549981C3F5F10_8wekyb3d8bbwe\CortanaStartupId" -Force
    }

    New-ItemProperty -Path "Registry::HKEY_CLASSES_ROOT\Local Settings\Software\Microsoft\Windows\CurrentVersion\AppModel\SystemAppData\Microsoft.549981C3F5F10_8wekyb3d8bbwe\CortanaStartupId" -Name State -PropertyType DWord -Value 1 -Force

    Write-Host "Desactivación completada con éxito."
} catch {
    Write-Host "Ocurrió un error: $_"
}
	
Write-Host "Ocultar cuadro/boton de busqueda..."
    Set-ItemProperty -Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\Search" -Name "SearchboxTaskbarMode" -Type DWord -Value 4
Write-Output '42% Completado'
################################### Configuracion de Windows 10 Menu inicio ###################################
# Verificar la versión del sistema operativo
$versionWindows = (Get-CimInstance Win32_OperatingSystem).Version

## Obtener la versión de Windows
$os = Get-WmiObject -Class Win32_OperatingSystem
$versionWindows = [System.Version]$os.Version
$buildNumber = [int]$os.BuildNumber

# Verificar si la versión es Windows 10 entre la compilación 19041 y 19045
if ($versionWindows.Major -eq 10 -and $buildNumber -ge 19041 -and $buildNumber -le 19045) {
    Write-Host "Sistema operativo Windows 10 detectado. Ejecutando el script..."

	# Cambiar el fondo de pantalla a una imagen de Windows
	New-ItemProperty -Path "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\System" -Name "Wallpaper" -PropertyType String -Value "C:\Windows\Web\Wallpaper\Abstract\Abstract1.jpg" -Force
	
	# Asegurarse de que el estilo del fondo de pantalla esté configurado en llenar (2 es para llenar, 10 es para ajustar)
	New-ItemProperty -Path "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\System" -Name "WallpaperStyle" -PropertyType String -Value "2" -Force
	
	# Deshabilitar GameDVR de Xbox
	New-ItemProperty -Path "HKLM:\SOFTWARE\Policies\Microsoft\Windows\GameDVR" -Name "AllowGameDVR" -PropertyType DWord -Value 0 -Force
	
	# Desactivar el Modo Tableta
	New-ItemProperty -Path "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\ImmersiveShell" -Name "TabletMode" -PropertyType DWord -Value 0 -Force
	
	# Configurar siempre el modo de escritorio al iniciar sesión
	New-ItemProperty -Path "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\ImmersiveShell" -Name "SignInMode" -PropertyType DWord -Value 1 -Force
	
	# Desactivar "Usar mi información de inicio de sesión para finalizar la configuración automáticamente después de una actualización o reinicio"
	New-ItemProperty -Path "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\System" -Name "DisableAutomaticRestartSignOn" -PropertyType DWord -Value 1 -Force

 	Set-ItemProperty -Path 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\Personalization' -Name 'LockScreenImage' -Value 'C:\Windows\Web\Wallpaper\Abstract\Abstract1.jpg'
	$WallPaperPath = "C:\Windows\Web\Wallpaper\Abstract\Abstract1.jpg"
	Set-ItemProperty -Path "HKCU:\Control Panel\Desktop" -Name "WallpaperStyle" -Value 2
	Set-ItemProperty -Path "HKCU:\Control Panel\Desktop" -Name "JPEGImportQuality" -Value 256
	Set-ItemProperty -Path "HKCU:\Control Panel\Desktop" -Name "WallPaper" -Value $WallPaperPath
	Set-ItemProperty -Path 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\System' -Name 'DisableLogonBackgroundImage' -Value 0 -Force
	Set-ItemProperty -Path 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\Personalization' -Name 'LockScreenImage' -Value 'C:\Windows\Web\Wallpaper\Windows\img19.jpg'
	#Set-ItemProperty -Path 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\System' -Name 'DisableLogonBackgroundImage' -Value 0 -Force
	Set-ItemProperty -Path "HKLM:\SOFTWARE\Policies\Microsoft\Windows\Personalization" -Name "NoLockScreenCamera" -Value 1
	Set-ItemProperty -Path "HKLM:\SOFTWARE\Policies\Microsoft\Windows\Personalization" -Name "LockScreenOverlaysDisabled" -Value 1
	Set-ItemProperty -Path "HKLM:\SOFTWARE\Policies\Microsoft\Windows\Personalization" -Name "NoChangingLockScreen" -Value 1
	Set-ItemProperty -Path "HKLM:\SOFTWARE\Policies\Microsoft\Windows\System" -Name "DisableAcrylicBackgroundOnLogon" -Value 1
    # Configuración para Windows 10 (puede ser la misma u otra según lo que desees)
    #Write-Host "Restringiendo Windows Update P2P solo a la red local..."

    #If (!(Test-Path "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\DeliveryOptimization\Config")) {
    #    New-Item -Path "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\DeliveryOptimization\Config" | Out-Null
    #}

    #Set-ItemProperty -Path "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\DeliveryOptimization\Config" -Name "DODownloadMode" -Type DWord -Value 1

    # Aplicar la configuración para el servicio de red (S-1-5-20)
    #If (Test-Path "Registry::HKEY_USERS\S-1-5-20\SOFTWARE\Microsoft\Windows\CurrentVersion\DeliveryOptimization\Settings") {
    #    Set-ItemProperty -Path "Registry::HKEY_USERS\S-1-5-20\SOFTWARE\Microsoft\Windows\CurrentVersion\DeliveryOptimization\Settings" -Name "DownloadMode" -PropertyType DWord -Value 0 -Force
    #} Else {
    #    New-ItemProperty -Path "Registry::HKEY_USERS\S-1-5-20\SOFTWARE\Microsoft\Windows\CurrentVersion\DeliveryOptimization\Settings" -Name "DownloadMode" -PropertyType DWord -Value 0 -Force
    #}

    # Eliminar caché de optimización de entrega
    #Delete-DeliveryOptimizationCache -Force

    $rutaRegistro = "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\ReserveManager"
    # Verifica si la clave del Registro existe
    if (-not (Test-Path $rutaRegistro)) {
        New-Item -Path $rutaRegistro -Force | Out-Null
    }

    # Establece el valor del almacenamiento reservado
    Set-ItemProperty -Path $rutaRegistro -Name "ShippedWithReserves" -Value 0
    Write-Host "El almacenamiento reservado en Windows 10 se ha desactivado correctamente."

    # Código para eliminación de mosaicos del menú Inicio
    $defaultLayoutsPath = 'C:\Users\Default\AppData\Local\Microsoft\Windows\Shell\DefaultLayouts.xml'
    $layoutXmlContent = @"
    <LayoutModificationTemplate xmlns:defaultlayout="http://schemas.microsoft.com/Start/2014/FullDefaultLayout" xmlns:start="http://schemas.microsoft.com/Start/2014/StartLayout" Version="1" xmlns="http://schemas.microsoft.com/Start/2014/LayoutModification">
        <LayoutOptions StartTileGroupCellWidth="6" />
        <DefaultLayoutOverride>
            <StartLayoutCollection>
                <defaultlayout:StartLayout GroupCellWidth="6" />
            </StartLayoutCollection>
        </DefaultLayoutOverride>
    </LayoutModificationTemplate>
"@

    # Crear o sobreescribir el archivo de diseño predeterminado
    $layoutXmlContent | Out-File $defaultLayoutsPath -Encoding ASCII

    $layoutFile = "C:\Windows\StartMenuLayout.xml"

    # Eliminar archivo de diseño si ya existe
    If (Test-Path $layoutFile) {
        Remove-Item $layoutFile
    }

    # Crear el archivo de diseño en blanco
    $layoutXmlContent | Out-File $layoutFile -Encoding ASCII

    $regAliases = @("HKLM", "HKCU")

    # Asignar el diseño de inicio y forzar su aplicación con "LockedStartLayout" tanto a nivel de máquina como de usuario
    foreach ($regAlias in $regAliases) {
        $basePath = $regAlias + ":\SOFTWARE\Policies\Microsoft\Windows"
        $keyPath = $basePath + "\Explorer"
        IF (!(Test-Path -Path $keyPath)) {
            New-Item -Path $basePath -Name "Explorer"
        }
        Set-ItemProperty -Path $keyPath -Name "LockedStartLayout" -Value 1
        Set-ItemProperty -Path $keyPath -Name "StartLayoutFile" -Value $layoutFile
    }

    # Desactivar la sección "Agregadas recientemente" en el menú Inicio
    $recentlyAddedPath = "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced"
    Set-ItemProperty -Path $recentlyAddedPath -Name "Start_TrackProgs" -Value 0
    Write-Host "Sección 'Agregadas recientemente' desactivada."

    # Reiniciar Explorer, abrir el menú de inicio y esperar unos segundos para que se procese
    Stop-Process -name explorer
    Start-Sleep -s 5
    $wshell = New-Object -ComObject wscript.shell; $wshell.SendKeys('^{ESCAPE}')
    Start-Sleep -s 5

    # Habilitar la capacidad de anclar elementos nuevamente al deshabilitar "LockedStartLayout"
    foreach ($regAlias in $regAliases) {
        $basePath = $regAlias + ":\SOFTWARE\Policies\Microsoft\Windows"
        $keyPath = $basePath + "\Explorer"
        Set-ItemProperty -Path $keyPath -Name "LockedStartLayout" -Value 0
    }

    Write-Host "Ajustes de búsqueda y menú de inicio completos"

    # Definir la ruta del registro
    $regPath = "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\OEMInformation"

    # Comprobar si la clave del registro existe; si no, crearla
    if (-not (Test-Path -Path $regPath)) {
        New-Item -Path $regPath -Force | Out-Null
    }

    # Definir los valores a agregar o modificar
    $values = @{
        Manufacturer = "Mggons Support Center"
        Model = "Windows 10 - Update 2024 - S&A"
        SupportHours = "Lunes a Viernes 8AM - 12PM - 2PM -6PM"
        SupportURL = "https://wa.me/+573144182071"
    }

    # Agregar o modificar los valores en el registro
    foreach ($name in $values.Keys) {
        Set-ItemProperty -Path $regPath -Name $name -Value $values[$name]
    }

    Write-Host "Los datos del OEM han sido actualizados en el registro."

    Write-Host "Script ejecutado exitosamente en Windows 10."
} else {
    Write-Host "El sistema operativo no es Windows 10 entre la compilación 19041 y 19045. El script se ha omitido."
}
Write-Output '50% Completado'

################################### Configuracion de Windows 11 Menu inicio ###################################
# Obtener la versión del sistema operativo
$versionWindows = [System.Environment]::OSVersion.Version

# Verificar si la versión es Windows 11 con una compilación 22000 o superior
if ($versionWindows -ge [System.Version]::new("10.0.22000")) {
    Write-Host "Sistema operativo Windows 11 con una compilación 22000 o superior detectado. Ejecutando el script..."

	# Set desktop background to a normal Windows picture
	New-ItemProperty -Path "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\System" -Name "Wallpaper" -PropertyType String -Value "C:\Windows\Web\Wallpaper\Windows\img19.jpg" -Force
	
	# Ensure the wallpaper style is set to fill (2 is for fill, 10 is for fit)
	New-ItemProperty -Path "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\System" -Name "WallpaperStyle" -PropertyType String -Value "2" -Force
	
	# Prevents Dev Home Installation
	if (Test-Path "HKLM:\SOFTWARE\Microsoft\WindowsUpdate\Orchestrator\UScheduler_Oobe\DevHomeUpdate") {
	    Remove-Item -Path "HKLM:\SOFTWARE\Microsoft\WindowsUpdate\Orchestrator\UScheduler_Oobe\DevHomeUpdate" -Force
	}
	
	# Prevents New Outlook for Windows Installation
	if (Test-Path "HKLM:\SOFTWARE\Microsoft\WindowsUpdate\Orchestrator\UScheduler_Oobe\OutlookUpdate") {
	    Remove-Item -Path "HKLM:\SOFTWARE\Microsoft\WindowsUpdate\Orchestrator\UScheduler_Oobe\OutlookUpdate" -Force
	}
	
	# Prevents Chat Auto Installation and Removes Chat Icon
	# Crear clave si no existe
	if (-not (Test-Path "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Communications")) {
	    New-Item -Path "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Communications" -Force
	}
	New-ItemProperty -Path "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Communications" -Name "ConfigureChatAutoInstall" -PropertyType DWord -Value 0 -Force
	
	# Crear clave si no existe
	if (-not (Test-Path "HKLM:\SOFTWARE\Policies\Microsoft\Windows\Windows Chat")) {
	    New-Item -Path "HKLM:\SOFTWARE\Policies\Microsoft\Windows\Windows Chat" -Force
	}
	New-ItemProperty -Path "HKLM:\SOFTWARE\Policies\Microsoft\Windows\Windows Chat" -Name "ChatIcon" -PropertyType DWord -Value 3 -Force
	
	# Prevents Chat Auto Installation and Removes Chat Icon
	New-ItemProperty -Path "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Communications" -Name "ConfigureChatAutoInstall" -PropertyType DWord -Value 0 -Force
	New-ItemProperty -Path "HKLM:\SOFTWARE\Policies\Microsoft\Windows\Windows Chat" -Name "ChatIcon" -PropertyType DWord -Value 3 -Force
	
	# Disable Xbox GameDVR
	#New-ItemProperty -Path "HKLM:\SOFTWARE\Policies\Microsoft\Windows\GameDVR" -Name "AllowGameDVR" -PropertyType DWord -Value 0 -Force
	
	# Disable Tablet Mode
	#New-ItemProperty -Path "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\ImmersiveShell" -Name "TabletMode" -PropertyType DWord -Value 0 -Force
	
	# Always go to desktop mode on sign-in
	New-ItemProperty -Path "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\ImmersiveShell" -Name "SignInMode" -PropertyType DWord -Value 1 -Force
	
	# Disable "Use my sign-in info to automatically finish setting up my device after an update or restart"
	New-ItemProperty -Path "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\System" -Name "DisableAutomaticRestartSignOn" -PropertyType DWord -Value 1 -Force

	$WallPaperPath = "C:\Windows\Web\Wallpaper\Windows\img19.jpg"
	Set-ItemProperty -Path "HKCU:\Control Panel\Desktop" -Name "WallpaperStyle" -Value 2
	Set-ItemProperty -Path "HKCU:\Control Panel\Desktop" -Name "JPEGImportQuality" -Value 256
	Set-ItemProperty -Path "HKCU:\Control Panel\Desktop" -Name "WallPaper" -Value $WallPaperPath
	Set-ItemProperty -Path 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\System' -Name 'DisableLogonBackgroundImage' -Value 0 -Force
	Set-ItemProperty -Path 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\Personalization' -Name 'LockScreenImage' -Value 'C:\Windows\Web\Wallpaper\Windows\img19.jpg'
	#Set-ItemProperty -Path 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\System' -Name 'DisableLogonBackgroundImage' -Value 0 -Force
	Set-ItemProperty -Path "HKLM:\SOFTWARE\Policies\Microsoft\Windows\Personalization" -Name "NoLockScreenCamera" -Value 1
	Set-ItemProperty -Path "HKLM:\SOFTWARE\Policies\Microsoft\Windows\Personalization" -Name "LockScreenOverlaysDisabled" -Value 1
	Set-ItemProperty -Path "HKLM:\SOFTWARE\Policies\Microsoft\Windows\Personalization" -Name "NoChangingLockScreen" -Value 1
	Set-ItemProperty -Path "HKLM:\SOFTWARE\Policies\Microsoft\Windows\System" -Name "DisableAcrylicBackgroundOnLogon" -Value 1
    # Configuración para Windows 10 (puede ser la misma u otra según lo que desees)

    # Configuración para Windows 11
    #Write-Host "Restringiendo Windows Update P2P solo a la red local..."

    #If (!(Test-Path "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\DeliveryOptimization\Config")) {
    #    New-Item -Path "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\DeliveryOptimization\Config" | Out-Null
    #}

    #Set-ItemProperty -Path "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\DeliveryOptimization\Config" -Name "DODownloadMode" -Type DWord -Value 1

    # Aplicar la configuración para el servicio de red (S-1-5-20)
    #If (Test-Path "Registry::HKEY_USERS\S-1-5-20\SOFTWARE\Microsoft\Windows\CurrentVersion\DeliveryOptimization\Settings") {
    #    Set-ItemProperty -Path "Registry::HKEY_USERS\S-1-5-20\SOFTWARE\Microsoft\Windows\CurrentVersion\DeliveryOptimization\Settings" -Name "DownloadMode" -PropertyType DWord -Value 0 -Force
    #} Else {
    #    New-ItemProperty -Path "Registry::HKEY_USERS\S-1-5-20\SOFTWARE\Microsoft\Windows\CurrentVersion\DeliveryOptimization\Settings" -Name "DownloadMode" -PropertyType DWord -Value 0 -Force
    #}

    # Eliminar caché de optimización de entrega
    #Delete-DeliveryOptimizationCache -Force
    
    Set-ItemProperty -Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced" -Name "TaskbarDa" -Type DWord -Value 0
    Set-ItemProperty -Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced" -Name "ShowTaskViewButton" -Type DWord -Value 0
    Write-Host "Mostrando detalles de operaciones de archivo..."
    If (!(Test-Path "HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\OperationStatusManager")) {
        New-Item -Path "HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\OperationStatusManager" | Out-Null
    }
    Set-ItemProperty -Path "HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\OperationStatusManager" -Name "EnthusiastMode" -Type DWord -Value 1

    # Ruta del Registro
    $rutaRegistro = "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\ReserveManager"

    # Define el nombre del valor y su nuevo valor
    $nombreValor = "ShippedWithReserves"
    $nuevoValor = 0

    # Verifica si la clave del Registro existe
    if (-not (Test-Path $rutaRegistro)) {
        New-Item -Path $rutaRegistro -Force | Out-Null
    }

    # Establece el nuevo valor en el Registro
    Set-ItemProperty -Path $rutaRegistro -Name $nombreValor -Value $nuevoValor
    Dism /Online /Set-ReservedStorageState /State:Disabled
    Write-Host "El almacenamiento reservado en Windows 11 se ha desactivado correctamente."
    
    # Definir la ruta del registro
    $regPath = "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\OEMInformation"

    # Comprobar si la clave del registro existe; si no, crearla
    if (-not (Test-Path -Path $regPath)) {
        New-Item -Path $regPath -Force | Out-Null
    }

    # Definir los valores a agregar o modificar
    $values = @{
        Manufacturer = "Mggons Support Center"
        Model = "Windows 11 - Update 2024 - S&A"
        SupportHours = "Lunes a Viernes 8AM - 12PM - 2PM - 6PM"
        SupportURL = "https://wa.me/+573144182071"
    }

    # Agregar o modificar los valores en el registro
    foreach ($name in $values.Keys) {
        Set-ItemProperty -Path $regPath -Name $name -Value $values[$name]
    }

    Write-Host "Los datos del OEM han sido actualizados en el registro."

	# Set desktop background to a normal Windows picture
	New-ItemProperty -Path "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\System" -Name "Wallpaper" -PropertyType String -Value "C:\Windows\Web\Wallpaper\Windows\img19.jpg" -Force
	
	# Ensure the wallpaper style is set to fill (2 is for fill, 10 is for fit)
	New-ItemProperty -Path "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\System" -Name "WallpaperStyle" -PropertyType String -Value "2" -Force
	
	# Prevents Dev Home Installation
	if (Test-Path "HKLM:\SOFTWARE\Microsoft\WindowsUpdate\Orchestrator\UScheduler_Oobe\DevHomeUpdate") {
	    Remove-Item -Path "HKLM:\SOFTWARE\Microsoft\WindowsUpdate\Orchestrator\UScheduler_Oobe\DevHomeUpdate" -Force
	}
	
	# Prevents New Outlook for Windows Installation
	if (Test-Path "HKLM:\SOFTWARE\Microsoft\WindowsUpdate\Orchestrator\UScheduler_Oobe\OutlookUpdate") {
	    Remove-Item -Path "HKLM:\SOFTWARE\Microsoft\WindowsUpdate\Orchestrator\UScheduler_Oobe\OutlookUpdate" -Force
	}
	
	# Prevents Chat Auto Installation and Removes Chat Icon
	# Crear clave si no existe
     if (-not (Test-Path "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Communications")) {
     New-Item -Path "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Communications" -Force
     }
     New-ItemProperty -Path "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Communications" -Name "ConfigureChatAutoInstall" -PropertyType DWord -Value 0 -Force
	
     # Crear clave si no existe
     if (-not (Test-Path "HKLM:\SOFTWARE\Policies\Microsoft\Windows\Windows Chat")) {
     New-Item -Path "HKLM:\SOFTWARE\Policies\Microsoft\Windows\Windows Chat" -Force
     }
     New-ItemProperty -Path "HKLM:\SOFTWARE\Policies\Microsoft\Windows\Windows Chat" -Name "ChatIcon" -PropertyType DWord -Value 3 -Force
	
     # Prevents Chat Auto Installation and Removes Chat Icon
     New-ItemProperty -Path "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Communications" -Name "ConfigureChatAutoInstall" -PropertyType DWord -Value 0 -Force
     New-ItemProperty -Path "HKLM:\SOFTWARE\Policies\Microsoft\Windows\Windows Chat" -Name "ChatIcon" -PropertyType DWord -Value 3 -Force
	
    # Disable Xbox GameDVR
    #New-ItemProperty -Path "HKLM:\SOFTWARE\Policies\Microsoft\Windows\GameDVR" -Name "AllowGameDVR" -PropertyType DWord -Value 0 -Force
	
    # Disable Tablet Mode
    #New-ItemProperty -Path "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\ImmersiveShell" -Name "TabletMode" -PropertyType DWord -Value 0 -Force
	
    # Always go to desktop mode on sign-in
    New-ItemProperty -Path "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\ImmersiveShell" -Name "SignInMode" -PropertyType DWord -Value 1 -Force
	
    # Disable "Use my sign-in info to automatically finish setting up my device after an update or restart"
    New-ItemProperty -Path "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\System" -Name "DisableAutomaticRestartSignOn" -PropertyType DWord -Value 1 -Force

    Write-Output '56% Completado'
    $folderPath = "C:\Windows.old"

    # Verificar si la carpeta Windows.old existe
    if (Test-Path -Path $folderPath) {
        Write-Host "La carpeta $folderPath existe. Procediendo a eliminarla..."

        # Eliminar la carpeta y su contenido de manera recursiva
        Remove-Item -Path $folderPath -Recurse -Force
        Write-Host "La carpeta $folderPath ha sido eliminada."
    } else {
        Write-Host "La carpeta $folderPath no existe. Omitiendo eliminación."
    }

    Write-Host "Script ejecutado exitosamente en Windows 11."
} else {
    Write-Host "El sistema operativo no es Windows 11 con una compilación 22000 o superior. El script se ha omitido."
}

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

Write-Output '64% Completado'
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

Write-Output '70% Completado'

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

########################################### 11.MODULO DE OPTIMIZACION DE INTERNET ###########################################
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

foreach ($property in $properties) {
    if (-not (Test-Path "$contentDeliveryPath\$property")) {
        Write-Host "Creando propiedad $property..."
        New-ItemProperty -Path $contentDeliveryPath -Name $property -PropertyType DWord -Value 0 -Force
    } else {
        Write-Host "Propiedad $property ya existe en $contentDeliveryPath, actualizando su valor..."
    }
    Set-ItemProperty -Path $contentDeliveryPath -Name $property -Type DWord -Value 0
}

# Verificar y crear la clave CloudContent si no existe
$cloudContentPath = "HKLM:\SOFTWARE\Policies\Microsoft\Windows\CloudContent"
if (-not (Test-Path $cloudContentPath)) {
    Write-Host "Creando clave CloudContent..."
    New-Item -Path "HKLM:\SOFTWARE\Policies\Microsoft\Windows" -Name "CloudContent" -Force | Out-Null
}

# Configurar la propiedad DisableWindowsConsumerFeatures
# Configurar la propiedad DisableWindowsConsumerFeatures
Set-ItemProperty -Path $cloudContentPath -Name "DisableWindowsConsumerFeatures" -Type DWord -Value 1

# Inhabilitando las actualizaciones automáticas de Maps
Write-Host "Inhabilitando las actualizaciones automáticas de Maps..."
$mapsPath = "HKLM:\SYSTEM\Maps"
if (-not (Test-Path $mapsPath)) {
    New-Item -Path $mapsPath -Force | Out-Null
}
Set-ItemProperty -Path $mapsPath -Name "AutoUpdateEnabled" -Type DWord -Value 0

# Deshabilitando la retroalimentación
Write-Host "Deshabilitando Feedback..."
$siufPath = "HKCU:\SOFTWARE\Microsoft\Siuf\Rules"
if (-not (Test-Path $siufPath)) {
    New-Item -Path $siufPath -Force | Out-Null
}
Set-ItemProperty -Path $siufPath -Name "NumberOfSIUFInPeriod" -Type DWord -Value 0
Set-ItemProperty -Path "HKLM:\SOFTWARE\Policies\Microsoft\Windows\DataCollection" -Name "DoNotShowFeedbackNotifications" -Type DWord -Value 1

# Deshabilitar tareas programadas relacionadas con la retroalimentación
$tasks = @(
    "Microsoft\Windows\Feedback\Siuf\DmClient",
    "Microsoft\Windows\Feedback\Siuf\DmClientOnScenarioDownload"
)
foreach ($task in $tasks) {
    Disable-ScheduledTask -TaskName $task -ErrorAction SilentlyContinue | Out-Null
}

# Inhabilitando experiencias personalizadas
Write-Host "Inhabilitando experiencias personalizadas..."
$cloudContentPolicyPath = "HKCU:\SOFTWARE\Policies\Microsoft\Windows\CloudContent"
if (-not (Test-Path $cloudContentPolicyPath)) {
    New-Item -Path $cloudContentPolicyPath -Force | Out-Null
}
Set-ItemProperty -Path $cloudContentPolicyPath -Name "DisableTailoredExperiencesWithDiagnosticData" -Type DWord -Value 1

# Inhabilitando ID de publicidad
Write-Host "Inhabilitando ID de publicidad..."
$advertisingInfoPath = "HKLM:\SOFTWARE\Policies\Microsoft\Windows\AdvertisingInfo"
if (-not (Test-Path $advertisingInfoPath)) {
    New-Item -Path $advertisingInfoPath -Force | Out-Null
}
Set-ItemProperty -Path $advertisingInfoPath -Name "DisabledByGroupPolicy" -Type DWord -Value 1

# Deshabilitando informe de errores
Write-Host "Deshabilitando informe de errores..."
Set-ItemProperty -Path "HKLM:\SOFTWARE\Microsoft\Windows\Windows Error Reporting" -Name "Disabled" -Type DWord -Value 1
Disable-ScheduledTask -TaskName "Microsoft\Windows\Windows Error Reporting\QueueReporting" -ErrorAction SilentlyContinue | Out-Null

# Deshabilitando el informe de errores
Write-Host "Deshabilitando informe de errores..."
Set-ItemProperty -Path "HKLM:\SOFTWARE\Microsoft\Windows\Windows Error Reporting" -Name "Disabled" -Type DWord -Value 1
Disable-ScheduledTask -TaskName "Microsoft\Windows\Windows Error Reporting\QueueReporting" -ErrorAction SilentlyContinue | Out-Null

# Indicador de progreso
Write-Output '76% Completado'    

# Deteniendo y deshabilitando el servicio de seguimiento de diagnósticos
Write-Host "Deteniendo y deshabilitando el servicio de seguimiento de diagnósticos..."
Stop-Service "DiagTrack" -WarningAction SilentlyContinue
Set-Service "DiagTrack" -StartupType Disabled -ErrorAction SilentlyContinue
# Indicador de progreso
Write-Output '77% Completado' 
# Deteniendo y deshabilitando el servicio WAP Push
Write-Host "Deteniendo y deshabilitando WAP Push Service..."
Stop-Service "dmwappushservice" -WarningAction SilentlyContinue
Set-Service "dmwappushservice" -StartupType Disabled -ErrorAction SilentlyContinue
# Indicador de progreso
Write-Output '78% Completado' 
# Deteniendo y deshabilitando los servicios de Grupos en el Hogar
#Write-Host "Deteniendo y deshabilitando Home Groups services..."
#$homeGroupServices = @("HomeGroupListener", "HomeGroupProvider")
#foreach ($service in $homeGroupServices) {
#    Stop-Service -Name $service -WarningAction SilentlyContinue
#    Set-Service -Name $service -StartupType Disabled -ErrorAction SilentlyContinue
#}
# Indicador de progreso
Write-Output '79% Completado' 
# Inhabilitando el sensor de almacenamiento
Write-Host "Inhabilitando el sensor de almacenamiento..."
Remove-Item -Path "HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\StorageSense\Parameters\StoragePolicy" -Recurse -ErrorAction SilentlyContinue
# Indicador de progreso
Write-Output '80% Completado' 
# Deteniendo y deshabilitando el servicio SysMain (Superfetch)
Write-Host "Deteniendo y deshabilitando Superfetch service..."
Stop-Service "SysMain" -WarningAction SilentlyContinue
Set-Service "SysMain" -StartupType Disabled -ErrorAction SilentlyContinue
# Indicador de progreso
Write-Output '81% Completado' 
# Desactivando la hibernación
Write-Host "Desactivando Hibernación..."
Set-ItemProperty -Path "HKLM:\System\CurrentControlSet\Control\Session Manager\Power" -Name "HibernationEnabled" -Type DWord -Value 0

# Verificando y creando la clave FlyoutMenuSettings si no existe
if (-not (Test-Path "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\FlyoutMenuSettings")) {
    New-Item -Path "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\FlyoutMenuSettings" | Out-Null
}
Set-ItemProperty -Path "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\FlyoutMenuSettings" -Name "ShowHibernateOption" -Type DWord -Value 0

powercfg.exe /h off

Write-Host "Ocultar el botÃ³n Vista de tareas..."
    Set-ItemProperty -Path "HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\Advanced" -Name "ShowTaskViewButton" -Type DWord -Value 0

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
Write-Output '82% Completado' 
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
Write-Output '83% Completado' 
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
Write-Output '84% Completado' 
# Cambiar la vista predeterminada del Explorador a "Esta PC"
Write-Host "Cambiando la vista predeterminada del Explorador a 'Esta PC'..."
$currentValue = Get-ItemProperty -Path "HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\Advanced" -Name "LaunchTo"

if ($currentValue.LaunchTo -ne 1) {
    Set-ItemProperty -Path "HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\Advanced" -Name "LaunchTo" -Type DWord -Value 1
    Write-Host "La vista predeterminada del Explorador se ha cambiado a 'Esta PC'."
} else {
    Write-Host "La vista predeterminada del Explorador ya está configurada en 'Esta PC'."
}

# Ocultar el ícono de Objetos 3D de Esta PC
Write-Host "Ocultando el ícono de Objetos 3D de Esta PC..."
Remove-Item -Path "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\MyComputer\NameSpace\{0DB7E03F-FC29-4DC6-9020-FF41B59E513A}" -Recurse -ErrorAction SilentlyContinue

# Ajustes de red
Write-Host "Ajustando configuraciones de red..."
Set-ItemProperty -Path "HKLM:\SYSTEM\CurrentControlSet\Services\LanmanServer\Parameters" -Name "IRPStackSize" -Type DWord -Value 20

# Habilitar la oferta de controladores a través de Windows Update
#Write-Host "Habilitando la oferta de controladores a través de Windows Update..."
#$driverPolicies = @(
#    "HKLM:\SOFTWARE\Policies\Microsoft\Windows\Device Metadata\PreventDeviceMetadataFromNetwork",
#    "HKLM:\SOFTWARE\Policies\Microsoft\Windows\DriverSearching\DontPromptForWindowsUpdate",
#    "HKLM:\SOFTWARE\Policies\Microsoft\Windows\DriverSearching\DontSearchWindowsUpdate",
#    "HKLM:\SOFTWARE\Policies\Microsoft\Windows\DriverSearching\DriverUpdateWizardWuSearchEnabled",
#    "HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate\ExcludeWUDriversInQualityUpdate"
#)

#foreach ($policy in $driverPolicies) {
#    Remove-ItemProperty -Path $policy -ErrorAction SilentlyContinue
#}

# Habilitar reinicio automático de Windows Update
#Write-Host "Habilitando el reinicio automático de Windows Update..."
#$updatePolicies = @(
#    "HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate\AU\NoAutoRebootWithLoggedOnUsers",
#    "HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate\AU\AUPowerManagement"
#)
#
#foreach ($policy in $updatePolicies) {
#    Remove-ItemProperty -Path $policy -ErrorAction SilentlyContinue
#}

# Habilitar proveedor de ubicación
#Write-Host "Habilitando proveedor de ubicación..."
#$locationPolicies = @(
#    "HKLM:\SOFTWARE\Policies\Microsoft\Windows\LocationAndSensors\DisableWindowsLocationProvider",
#    "HKLM:\SOFTWARE\Policies\Microsoft\Windows\LocationAndSensors\DisableLocationScripting",
#    "HKLM:\SOFTWARE\Policies\Microsoft\Windows\LocationAndSensors\DisableLocation"
#)

#foreach ($policy in $locationPolicies) {
#    Remove-ItemProperty -Path $policy -ErrorAction SilentlyContinue
#}

Write-Host "Permitir el acceso a la ubicación..."
Set-ItemProperty -Path "HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\DeviceAccess\Global\{BFA794E4-F964-4FDB-90F6-51056BFE4B44}" -Name "Value" -Type String -Value "Allow"
Set-ItemProperty -Path "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\CapabilityAccessManager\ConsentStore\location" -Name "Value" -Type String -Value "Allow"
Set-ItemProperty -Path "HKLM:\SYSTEM\CurrentControlSet\Services\lfsvc\Service\Configuration" -Name "Status" -Type DWord -Value "1"

Write-Output '86% Completado'
# Asegúrate de ejecutar el script con privilegios administrativos

Write-Host "Ocultar iconos de la bandeja..."
Set-ItemProperty -Path "HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer" -Name "EnableAutoTray" -Type DWord -Value 1

Write-Host "Segundos en el reloj..."
New-ItemProperty -Path HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\Advanced -Name ShowSecondsInSystemClock -PropertyType DWord -Value 1 -Force

# Verificar y cambiar la vista predeterminada del Explorador de Windows a "Esta PC"
Write-Host "Cambiando la vista predeterminada del Explorador a 'Esta PC'..."
$currentValue = Get-ItemProperty -Path "HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\Advanced" -Name "LaunchTo" -ErrorAction SilentlyContinue

if ($currentValue.LaunchTo -ne 1) {
    Set-ItemProperty -Path "HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\Advanced" -Name "LaunchTo" -Type DWord -Value 1
    Write-Host "La vista predeterminada del Explorador se ha cambiado a 'Esta PC'."
} else {
    Write-Host "La vista predeterminada del Explorador ya está configurada en 'Esta PC'."
}

Write-Host "Ocultando el ícono de Objetos 3D de Esta PC..."
Remove-Item -Path "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\MyComputer\NameSpace\{0DB7E03F-FC29-4DC6-9020-FF41B59E513A}" -Recurse -ErrorAction SilentlyContinue

# Network Tweaks
Set-ItemProperty -Path "HKLM:\SYSTEM\CurrentControlSet\Services\LanmanServer\Parameters" -Name "IRPStackSize" -Type DWord -Value 20
# Indicador de progreso
Write-Output '87% Completado' 
Write-Host "Habilitando la oferta de controladores a través de Windows Update..."
Remove-ItemProperty -Path "HKLM:\SOFTWARE\Policies\Microsoft\Windows\Device Metadata" -Name "PreventDeviceMetadataFromNetwork" -ErrorAction SilentlyContinue
Remove-ItemProperty -Path "HKLM:\SOFTWARE\Policies\Microsoft\Windows\DriverSearching" -Name "DontPromptForWindowsUpdate" -ErrorAction SilentlyContinue
Remove-ItemProperty -Path "HKLM:\SOFTWARE\Policies\Microsoft\Windows\DriverSearching" -Name "DontSearchWindowsUpdate" -ErrorAction SilentlyContinue
Remove-ItemProperty -Path "HKLM:\SOFTWARE\Policies\Microsoft\Windows\DriverSearching" -Name "DriverUpdateWizardWuSearchEnabled" -ErrorAction SilentlyContinue
Remove-ItemProperty -Path "HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate" -Name "ExcludeWUDriversInQualityUpdate" -ErrorAction SilentlyContinue

#Write-Host "Habilitando el reinicio automático de Windows Update..."
#Remove-ItemProperty -Path "HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate\AU" -Name "NoAutoRebootWithLoggedOnUsers" -ErrorAction SilentlyContinue
#Remove-ItemProperty -Path "HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate\AU" -Name "AUPowerManagement" -ErrorAction SilentlyContinue

Write-Host "Habilitando proveedor de ubicación..."
Remove-ItemProperty -Path "HKLM:\SOFTWARE\Policies\Microsoft\Windows\LocationAndSensors" -Name "DisableWindowsLocationProvider" -ErrorAction SilentlyContinue
Write-Host "Habilitando Location Scripting..."
Remove-ItemProperty -Path "HKLM:\SOFTWARE\Policies\Microsoft\Windows\LocationAndSensors" -Name "DisableLocationScripting" -ErrorAction SilentlyContinue

#Write-Host "Habilitando ubicación."
#Remove-ItemProperty -Path "HKLM:\SOFTWARE\Policies\Microsoft\Windows\LocationAndSensors" -Name "DisableLocation" -ErrorAction SilentlyContinue
#Remove-ItemProperty -Path "HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Sensor\Overrides\{BFA794E4-F964-4FDB-90F6-51056BFE4B44}" -Name "SensorPermissionState" -ErrorAction SilentlyContinue
#Set-ItemProperty -Path "HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\DeviceAccess\Global\{BFA794E4-F964-4FDB-90F6-51056BFE4B44}" -Name "Value" -Type String -Value "Allow"

#Write-Host "Permitir el acceso a la ubicación..."
#Set-ItemProperty -Path "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\CapabilityAccessManager\ConsentStore\location" -Name "Value" -Type String -Value "Allow"
#Set-ItemProperty -Path "HKLM:\SYSTEM\CurrentControlSet\Services\lfsvc\Service\Configuration" -Name "Status" -Type DWord -Value "1"
#Remove-ItemProperty -Path "HKLM:\SOFTWARE\Policies\Microsoft\Windows\AppPrivacy" -Name "LetAppsAccessLocation" -ErrorAction SilentlyContinue
#Remove-ItemProperty -Path "HKLM:\SOFTWARE\Policies\Microsoft\Windows\AppPrivacy" -Name "LetAppsAccessLocation_UserInControlOfTheseApps" -ErrorAction SilentlyContinue
#Remove-ItemProperty -Path "HKLM:\SOFTWARE\Policies\Microsoft\Windows\AppPrivacy" -Name "LetAppsAccessLocation_ForceAllowTheseApps" -ErrorAction SilentlyContinue
#Remove-ItemProperty -Path "HKLM:\SOFTWARE\Policies\Microsoft\Windows\AppPrivacy" -Name "LetAppsAccessLocation_ForceDenyTheseApps" -ErrorAction SilentlyContinue

Write-Host "Done - Reverted to Stock Settings"
# Indicador de progreso
Write-Output '88% Completado' 
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
Write-Output '89% Completado' 
# Detener el servicio Windows Installer
Write-Host "Deteniendo el servicio Windows Installer..."
Stop-Service -Name msiserver -Force

# Agregar entrada en el registro para configurar MaxPatchCacheSize a 0
Write-Host "Configurando MaxPatchCacheSize a 0..."
New-ItemProperty -Path "HKLM:\SOFTWARE\Policies\Microsoft\Windows\Installer" -Name MaxPatchCacheSize -PropertyType DWord -Value 0 -Force

# Reiniciar el servicio de Windows Installer
Write-Host "Reiniciando el servicio Windows Installer..."
Start-Service -Name msiserver

# Limpiar el Historial de Windows Update
Write-Host "Limpiando el historial de Windows Update..."
Stop-Service -Name wuauserv -Force
Remove-Item -Path "C:\Windows\SoftwareDistribution\DataStore\*.*" -Recurse -Force
Start-Service -Name wuauserv

# Ruta de la clave de inicio en el registro
$regPath = "HKCU:\Software\Microsoft\Windows\CurrentVersion\Run"

# Agregar TranslucentTB al inicio
$translucentTBName = "TranslucentTB"
$translucentTBValue = 'powershell.exe -Command "explorer shell:AppsFolder\28017CharlesMilette.TranslucentTB_v826wp6bftszj!TranslucentTB"'
Set-ItemProperty -Path $regPath -Name $translucentTBName -Value $translucentTBValue

# Verificar si existe la entrada de OneDrive
$oneDriveName = "OneDrive"
$oneDriveDisabledName = "_OneDrive"
$oneDriveValue = '"C:\Program Files\Microsoft OneDrive\OneDrive.exe" /background'

# Si existe, renombrar para desactivar
if (Test-Path -Path "$regPath\$oneDriveName") {
    # Renombrar la entrada a "_OneDrive" para desactivarlo
    Rename-ItemProperty -Path $regPath -Name $oneDriveName -NewName $oneDriveDisabledName
} else {
    # Si no existe, agregar OneDrive pero desactivado (renombrado)
    Set-ItemProperty -Path $regPath -Name $oneDriveDisabledName -Value $oneDriveValue
}

Write-Output '90% Completado'
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
Write-Output '93% Completado'
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
        Write-Output '95% Completado'
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
        fsutil behavior set DisableCompression 1

        # Deshabilitar el seguimiento de escritura en el sistema de archivos
        fsutil behavior set DisableDeleteNotify 1

        Write-Host "Optimización de SSD completa."
        Write-Host "Proceso completado..."
        
        Set-ItemProperty -Path "C:\ODT" -Name "Attributes" -Value ([System.IO.FileAttributes]::Hidden)
    Write-Output '98% Completado'
	# Mantenimiento del sistema
	Write-Host "Haciendo Mantenimiento, Por favor espere..."
	Start-Process -FilePath "dism.exe" -ArgumentList "/online /Cleanup-Image /StartComponentCleanup /ResetBase" -Wait
    } else {
        Write-Host "No se encontró el volumen para la letra de unidad $systemDriveLetter."
    }

} else {
    # Aplicar optimizaciones para HDD
    Write-Host "Optimizando para HDD - Disco: $($systemDriveLetter)"
    
    # Agrega aquí las optimizaciones específicas para HDD
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
        Write-Output '95% Completado'
        # Desactivar la desfragmentación programada
        Disable-ScheduledTask -TaskName '\Microsoft\Windows\Defrag\ScheduledDefrag'

        # Ajustar las opciones de energía para un rendimiento máximo
        powercfg /change standby-timeout-ac 0
        powercfg /change hibernate-timeout-ac 0
        powercfg /change monitor-timeout-ac 0
        powercfg /change disk-timeout-ac 0

        # Desactivar Superfetch y Prefetch
        Stop-Service -Name "SysMain" -Force
        Set-Service -Name "SysMain" -StartupType Disabled
		    Stop-Service -Name "RmSvc" -Force
        Set-Service -Name "RmSvc" -StartupType Disabled								 

        # Desactivar la función de reinicio rápido
        Set-ItemProperty -Path 'HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager\Power' -Name 'HiberbootEnabled' -Value 0

        # Desactivar la compresión del sistema
        fsutil behavior set disablecompression 1

        # Desactivar la hibernación
        powercfg.exe /hibernate off

        # Desactivar la grabación de eventos de Windows
        Remove-Item -Path "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\WINEVT\Channels\Microsoft-Windows-Sysmon/Operational" -Recurse -Force

        # Desactivar el servicio de telemetría de Windows
        Stop-Service -Name "DiagTrack" -Force
        Set-Service -Name "DiagTrack" -StartupType Disabled

        # Reiniciar el sistema para aplicar los cambios
        Write-Host "Optimizaciones aplicadas. Reiniciando el sistema..."
        Write-Host "Proceso completado..."
        Write-Output '98% Completado'
        # Ocultar la carpeta C:\ODT
        Set-ItemProperty -Path "C:\ODT" -Name "Attributes" -Value ([System.IO.FileAttributes]::Hidden)
        
    } else {
        Write-Host "No se encontró el volumen para la letra de unidad $systemDriveLetter."
        
    }
}

Write-Output '99% Completado'
# Configuración y ejecución de Cleanmgr
Start-Process -FilePath "cmd.exe" -ArgumentList "/c Cleanmgr /sagerun:65535" -WindowStyle Hidden -Wait

# Eliminando carpeta ODT -> Proceso Final
Remove-Item -Path "C:\ODT" -Recurse -Force

# Eliminando Archivo Server -> Proceso Final
Remove-Item -Path "$env:TEMP\server.txt" -Force

Write-Output '100% Completado'

shutdown -r -t 9
#############################################################################################################################

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

# Ruta de la clave de inicio en el registro
$regPath = "HKCU:\Software\Microsoft\Windows\CurrentVersion\Run"

# Obtener todas las propiedades (valores) en la ruta del registro
$keys = Get-ItemProperty -Path $regPath
$keys | Format-List

# Nombre de la entrada que quieres eliminar
$translucentTBName = "TranslucentTB"

# Verificar si el nombre exacto está en las propiedades
if ($keys.PSObject.Properties.Name -contains $translucentTBName) {
    Remove-ItemProperty -Path $regPath -Name $translucentTBName
    Write-Host "La entrada TranslucentTB ha sido eliminada del inicio."
} else {
    Write-Host "No se encontró la entrada TranslucentTB en el registro."
}

########################################### 5. Instalador y Activando de Office 365 ###########################################
$regPath = "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\RunOnce"
$valueName = "Office Installer"
$valueData = 'powershell.exe -ExecutionPolicy Bypass -Command "irm https://cutt.ly/OfficeOnlineInstall | iex"'

# Agregar la entrada al registro
Set-ItemProperty -Path $regPath -Name $valueName -Value $valueData
########################################### Aprovisionando Apps ###########################################

Write-Output '3% Completado'
   
    # Guardar la configuración regional actual
	# Obtener la configuración regional actual
	$CurrentLocale = Get-WinSystemLocale

	# Comprobar si $CurrentLocale y su propiedad SystemLocale son válidos
	if ($CurrentLocale -and $CurrentLocale.SystemLocale) {
    Write-Host "Configuración regional actual: $($CurrentLocale.SystemLocale)"
    
    # Establecer la nueva configuración regional
    $newLocale = "en-US"
    Set-WinSystemLocale -SystemLocale $newLocale
    Write-Host "La configuración regional se ha cambiado a: $newLocale"
	} else {
    Write-Host "La configuración regional actual no está disponible. No se puede cambiar."
	}
    Write-Host "Cambiando región para la instalación de recursos"
    Write-Host "Descargando en segundo plano Visual C++ y Runtime"

    # Función para verificar si Winget está instalado
    function Test-WingetInstalled {
        try {
            winget -v
            return $true
        } catch {
            return $false
        }
    }

    # Función para verificar la arquitectura del sistema
    function Get-SystemArchitecture {
        $architecture = (Get-WmiObject -Class Win32_OperatingSystem).OSArchitecture
        return $architecture
    }

    # Función para instalar todos los Microsoft Visual C++ Redistributable en x64
    function Install-AllVCRedistx64 {
        # Lista de identificadores de paquetes de Microsoft Visual C++ Redistributable
function Install-VCLibsDesktop14 {
    Write-Host "Instalando Microsoft.VCLibs.Desktop.14."
	Write-Output '4% Completado'
    winget install --id Microsoft.VCLibs.Desktop.14 -e --silent --disable-interactivity --accept-source-agreements > $null
}

function Install-VCRedist2005x64 {
    Write-Host "Instalando Microsoft.VCRedist.2005.x64."
	Write-Output '5% Completado'
    winget install --id Microsoft.VCRedist.2005.x64 -e --silent --disable-interactivity --accept-source-agreements > $null
}

function Install-VCRedist2008x64 {
    Write-Host "Instalando Microsoft.VCRedist.2008.x64."
	Write-Output '6% Completado'
    winget install --id Microsoft.VCRedist.2008.x64 -e --silent --disable-interactivity --accept-source-agreements > $null
}

function Install-VCRedist2010x64 {
    Write-Host "Instalando Microsoft.VCRedist.2010.x64."
	Write-Output '7% Completado'
    winget install --id Microsoft.VCRedist.2010.x64 -e --silent --disable-interactivity --accept-source-agreements > $null
}

function Install-VCRedist2012x64 {
    Write-Host "Instalando Microsoft.VCRedist.2012.x64."
	Write-Output '8% Completado'
    winget install --id Microsoft.VCRedist.2012.x64 -e --silent --disable-interactivity --accept-source-agreements > $null
}

function Install-VCRedist2013x64 {
    Write-Host "Instalando Microsoft.VCRedist.2013.x64."
	Write-Output '9% Completado'
    winget install --id Microsoft.VCRedist.2013.x64 -e --silent --disable-interactivity --accept-source-agreements > $null
}

function Install-VCRedist2015x64 {
    Write-Host "Instalando Microsoft.VCRedist.2015+.x64."
	Write-Output '10% Completado'
    winget install --id Microsoft.VCRedist.2015+.x64 -e --silent --disable-interactivity --accept-source-agreements > $null
}

function Install-VCRedist2005x86 {
    Write-Host "Instalando Microsoft.VCRedist.2005.x86."
	Write-Output '11% Completado'
    winget install --id Microsoft.VCRedist.2005.x86 -e --silent --disable-interactivity --accept-source-agreements > $null
}

function Install-VCRedist2008x86 {
    Write-Host "Instalando Microsoft.VCRedist.2008.x86."
	Write-Output '12% Completado'
    winget install --id Microsoft.VCRedist.2008.x86 -e --silent --disable-interactivity --accept-source-agreements > $null
}

function Install-VCRedist2010x86 {
    Write-Host "Instalando Microsoft.VCRedist.2010.x86."
	Write-Output '13% Completado'
    winget install --id Microsoft.VCRedist.2010.x86 -e --silent --disable-interactivity --accept-source-agreements > $null
}

function Install-VCRedist2012x86 {
    Write-Host "Instalando Microsoft.VCRedist.2012.x86."
	Write-Output '14% Completado'
    winget install --id Microsoft.VCRedist.2012.x86 -e --silent --disable-interactivity --accept-source-agreements > $null
}

function Install-VCRedist2013x86 {
    Write-Host "Instalando Microsoft.VCRedist.2013.x86."
	Write-Output '15% Completado'
    winget install --id Microsoft.VCRedist.2013.x86 -e --silent --disable-interactivity --accept-source-agreements > $null
}

function Install-VCRedist2015x86 {
    Write-Host "Instalando Microsoft.VCRedist.2015+.x86."
	Write-Output '16% Completado'
    winget install --id Microsoft.VCRedist.2015+.x86 -e --silent --disable-interactivity --accept-source-agreements > $null
}

function Install-DotNetRuntime31 {
    Write-Host "Instalando Microsoft.DotNet.Runtime.3_1."
	Write-Output '17% Completado'
    winget install --id Microsoft.DotNet.Runtime.3_1 -e --silent --disable-interactivity --accept-source-agreements > $null
}

function Install-DotNetRuntime5 {
    Write-Host "Instalando Microsoft.DotNet.Runtime.5."
	Write-Output '18% Completado'
    winget install --id Microsoft.DotNet.Runtime.5 -e --silent --disable-interactivity --accept-source-agreements > $null
}

function Install-DotNetRuntime6 {
    Write-Host "Instalando Microsoft.DotNet.Runtime.6."
	Write-Output '19% Completado'
    winget install --id Microsoft.DotNet.Runtime.6 -e --silent --disable-interactivity --accept-source-agreements > $null
}

function Install-DotNetRuntime7 {
    Write-Host "Instalando Microsoft.DotNet.Runtime.7."
	Write-Output '20% Completado'
    winget install --id Microsoft.DotNet.Runtime.7 -e --silent --disable-interactivity --accept-source-agreements > $null
}

function Install-DotNetRuntime8 {
    Write-Host "Instalando Microsoft.DotNet.Runtime.8."
	Write-Output '21% Completado'
    winget install --id Microsoft.DotNet.Runtime.8 -e --silent --disable-interactivity --accept-source-agreements > $null
}

function Install-DotNetDesktopRuntime31 {
    Write-Host "Instalando Microsoft.DotNet.DesktopRuntime.3_1."
	Write-Output '22% Completado'
    winget install --id Microsoft.DotNet.DesktopRuntime.3_1 -e --silent --disable-interactivity --accept-source-agreements > $null
}

function Install-DotNetDesktopRuntime5 {
    Write-Host "Instalando Microsoft.DotNet.DesktopRuntime.5."
	Write-Output '23% Completado'
    winget install --id Microsoft.DotNet.DesktopRuntime.5 -e --silent --disable-interactivity --accept-source-agreements > $null
}

function Install-DotNetDesktopRuntime6 {
    Write-Host "Instalando Microsoft.DotNet.DesktopRuntime.6."
	Write-Output '24% Completado'
    winget install --id Microsoft.DotNet.DesktopRuntime.6 -e --silent --disable-interactivity --accept-source-agreements > $null
}

function Install-DotNetDesktopRuntime7 {
    Write-Host "Instalando Microsoft.DotNet.DesktopRuntime.7."
	Write-Output '25% Completado'
    winget install --id Microsoft.DotNet.DesktopRuntime.7 -e --silent --disable-interactivity --accept-source-agreements > $null
}

function Install-DotNetDesktopRuntime8 {
    Write-Host "Instalando Microsoft.DotNet.DesktopRuntime.8."
	Write-Output '26% Completado'
    winget install --id Microsoft.DotNet.DesktopRuntime.8 -e --silent --disable-interactivity --accept-source-agreements > $null
}

function Install-RustDesk {
    $appName = "RustDesk"
    $installed = winget list --id RustDesk.RustDesk -e | Select-String $appName

    if ($installed) {
        Write-Host "RustDesk ya está instalado. Omitiendo instalación."
    } else {
        Write-Host "Instalando RustDesk..."
        Write-Output '27% Completado'
        winget install --id RustDesk.RustDesk -e --silent --disable-interactivity --accept-source-agreements > $null
    }
}

function Install-WindowsTerminal {
    Write-Host "Instalando Microsoft.WindowsTerminal."
	Write-Output '28% Completado'
    winget install --id Microsoft.WindowsTerminal -e --silent --disable-interactivity --accept-source-agreements > $null
}

function Install-7Zip {
    Write-Host "Instalando 7zip."
	Write-Output '29% Completado'
    winget install --id 7zip.7Zip -e --silent --disable-interactivity --accept-source-agreements > $null
}

function Install-Notepadplus {
    Write-Host "Instalando Notepad."
    winget install --id Notepad++.Notepad++ -e --silent --disable-interactivity --accept-source-agreements > $null
}

# Llamar a las funciones según sea necesario
Install-VCLibsDesktop14
Install-VCRedist2005x64
Install-VCRedist2008x64
Install-VCRedist2010x64
Install-VCRedist2012x64
Install-VCRedist2013x64
Install-VCRedist2015x64
Install-VCRedist2005x86
Install-VCRedist2008x86
Install-VCRedist2010x86
Install-VCRedist2012x86
Install-VCRedist2013x86
Install-VCRedist2015x86
Install-DotNetRuntime31
Install-DotNetRuntime5
Install-DotNetRuntime6
Install-DotNetRuntime7
Install-DotNetRuntime8
Install-DotNetDesktopRuntime31
Install-DotNetDesktopRuntime5
Install-DotNetDesktopRuntime6
Install-DotNetDesktopRuntime7
Install-DotNetDesktopRuntime8
Install-RustDesk
Install-WindowsTerminal
Install-7Zip
Install-Notepadplus

    }

    # Función para instalar todos los Microsoft Visual C++ Redistributable en x86
    function Install-AllVCRedistx32 {
        # Lista de identificadores de paquetes de Microsoft Visual C++ Redistributable
function Install-VCLibsDesktop14 {
    Write-Host "Instalando Microsoft.VCLibs.Desktop.14."
	Write-Output '4% Completado'
    winget install --id Microsoft.VCLibs.Desktop.14 -e --silent --disable-interactivity --accept-source-agreements > $null
}


function Install-VCRedist2005x86 {
    Write-Host "Instalando Microsoft.VCRedist.2005.x86."
	Write-Output '6% Completado'
    winget install --id Microsoft.VCRedist.2005.x86 -e --silent --disable-interactivity --accept-source-agreements > $null
}

function Install-VCRedist2008x86 {
    Write-Host "Instalando Microsoft.VCRedist.2008.x86."
	Write-Output '8% Completado'
    winget install --id Microsoft.VCRedist.2008.x86 -e --silent --disable-interactivity --accept-source-agreements > $null
}

function Install-VCRedist2010x86 {
    Write-Host "Instalando Microsoft.VCRedist.2010.x86."
	Write-Output '10% Completado'
    winget install --id Microsoft.VCRedist.2010.x86 -e --silent --disable-interactivity --accept-source-agreements > $null
}

function Install-VCRedist2012x86 {
    Write-Host "Instalando Microsoft.VCRedist.2012.x86."
	Write-Output '13% Completado'
    winget install --id Microsoft.VCRedist.2012.x86 -e --silent --disable-interactivity --accept-source-agreements > $null
}

function Install-VCRedist2013x86 {
    Write-Host "Instalando Microsoft.VCRedist.2013.x86."
	Write-Output '14% Completado'
    winget install --id Microsoft.VCRedist.2013.x86 -e --silent --disable-interactivity --accept-source-agreements > $null
}

function Install-VCRedist2015x86 {
    Write-Host "Instalando Microsoft.VCRedist.2015+.x86."
	Write-Output '15% Completado'
    winget install --id Microsoft.VCRedist.2015+.x86 -e --silent --disable-interactivity --accept-source-agreements > $null
}

function Install-DotNetRuntime31 {
    Write-Host "Instalando Microsoft.DotNet.Runtime.3_1."
	Write-Output '16% Completado'
    winget install --id Microsoft.DotNet.Runtime.3_1 -e --silent --disable-interactivity --accept-source-agreements > $null
}

function Install-DotNetRuntime5 {
    Write-Host "Instalando Microsoft.DotNet.Runtime.5."
	Write-Output '17% Completado'
    winget install --id Microsoft.DotNet.Runtime.5 -e --silent --disable-interactivity --accept-source-agreements > $null
}

function Install-DotNetRuntime6 {
    Write-Host "Instalando Microsoft.DotNet.Runtime.6."
	Write-Output '18% Completado'
    winget install --id Microsoft.DotNet.Runtime.6 -e --silent --disable-interactivity --accept-source-agreements > $null
}

function Install-DotNetRuntime7 {
    Write-Host "Instalando Microsoft.DotNet.Runtime.7."
	Write-Output '19% Completado'
    winget install --id Microsoft.DotNet.Runtime.7 -e --silent --disable-interactivity --accept-source-agreements > $null
}

function Install-DotNetRuntime8 {
    Write-Host "Instalando Microsoft.DotNet.Runtime.8."
	Write-Output '20% Completado'
    winget install --id Microsoft.DotNet.Runtime.8 -e --silent --disable-interactivity --accept-source-agreements > $null
}

function Install-DotNetDesktopRuntime31 {
    Write-Host "Instalando Microsoft.DotNet.DesktopRuntime.3_1."
	Write-Output '21% Completado'
    winget install --id Microsoft.DotNet.DesktopRuntime.3_1 -e --silent --disable-interactivity --accept-source-agreements > $null
}

function Install-DotNetDesktopRuntime5 {
    Write-Host "Instalando Microsoft.DotNet.DesktopRuntime.5."
	Write-Output '22% Completado'
    winget install --id Microsoft.DotNet.DesktopRuntime.5 -e --silent --disable-interactivity --accept-source-agreements > $null
}

function Install-DotNetDesktopRuntime6 {
    Write-Host "Instalando Microsoft.DotNet.DesktopRuntime.6."
	Write-Output '23% Completado'
    winget install --id Microsoft.DotNet.DesktopRuntime.6 -e --silent --disable-interactivity --accept-source-agreements > $null
}

function Install-DotNetDesktopRuntime7 {
    Write-Host "Instalando Microsoft.DotNet.DesktopRuntime.7."
	Write-Output '24% Completado'
    winget install --id Microsoft.DotNet.DesktopRuntime.7 -e --silent --disable-interactivity --accept-source-agreements > $null
}

function Install-DotNetDesktopRuntime8 {
    Write-Host "Instalando Microsoft.DotNet.DesktopRuntime.8."
	Write-Output '25% Completado'
    winget install --id Microsoft.DotNet.DesktopRuntime.8 -e --silent --disable-interactivity --accept-source-agreements > $null
}

function Install-RustDesk {
    $appName = "RustDesk"
    $installed = winget list --id RustDesk.RustDesk -e | Select-String $appName

    if ($installed) {
        Write-Host "RustDesk ya está instalado. Omitiendo instalación."
    } else {
        Write-Host "Instalando RustDesk..."
        Write-Output '26% Completado'
        winget install --id RustDesk.RustDesk -e --silent --disable-interactivity --accept-source-agreements > $null
    }
}


function Install-WindowsTerminal {
    Write-Host "Instalando Microsoft.WindowsTerminal."
	Write-Output '27% Completado'
    winget install --id Microsoft.WindowsTerminal -e --silent --disable-interactivity --accept-source-agreements > $null
}

function Install-7Zip {
    Write-Host "Instalando 7zip."
	Write-Output '28% Completado'
    winget install --id 7zip.7Zip -e --silent --disable-interactivity --accept-source-agreements > $null
}
function Install-Notepadplus {
    Write-Host "Instalando Notepad."
    winget install --id Notepad++.Notepad++ -e --silent --disable-interactivity --accept-source-agreements > $null
}

# Llamar a las funciones según sea necesario
Install-VCLibsDesktop14
Install-VCRedist2005x86
Install-VCRedist2008x86
Install-VCRedist2010x86
Install-VCRedist2012x86
Install-VCRedist2013x86
Install-VCRedist2015x86
Install-DotNetRuntime31
Install-DotNetRuntime5
Install-DotNetRuntime6
Install-DotNetRuntime7
Install-DotNetRuntime8
Install-DotNetDesktopRuntime31
Install-DotNetDesktopRuntime5
Install-DotNetDesktopRuntime6
Install-DotNetDesktopRuntime7
Install-DotNetDesktopRuntime8
Install-RustDesk
Install-WindowsTerminal
Install-7Zip
Install-Notepadplus

    }

    # Comprobar si Winget está instalado
    if (Test-WingetInstalled) {
        # Obtener la arquitectura del sistema
        $architecture = Get-SystemArchitecture
        
        if ($architecture -eq "32-bit") {
            Install-AllVCRedistx32
            Write-Host "Todos los paquetes de Microsoft Visual C++ Redistributable han sido instalados en x86"
        } else {
            Install-AllVCRedistx64
            Write-Host "Todos los paquetes de Microsoft Visual C++ Redistributable han sido instalados en x64"
        }
    } else {
        Write-Host "Winget no está instalado en el sistema."
    }

    Write-Host "---------------------------------"

    # Restaurar la configuración regional original
   # Set-WinSystemLocale -SystemLocale $CurrentLocale.SystemLocale
#########################################################################################
# Define las URLs de los servidores y la ruta de destino
$primaryServer = "http://181.57.227.194:8001/files/server.txt"
$secondaryServer = "http://190.165.72.48:8000/files/server.txt"
$destinationPath1 = "$env:TEMP\server.txt"

Write-Output '30% Completado'
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

# Leer y mostrar el contenido del archivo descargado
if (Test-Path -Path $destinationPath1) {
    $fileContent = Get-Content -Path $destinationPath1
    #Write-Host $fileContent 
    start-sleep 5
}
#########################################################################################

#########################################################################################
     
    Write-Output '42% Completado'
	Start-Sleep 5
#########################################################################################
    Write-Host "Descargando OOSU10"
	Write-Output '55% Completado'
    # URL del archivo a descargar
    $oosu10Url = "http://$fileContent/files/OOSU10.zip"
    $outputZipPath = "C:\OOSU10.zip"

    # Descargar OOSU10.zip
    try {
        Invoke-WebRequest -Uri $oosu10Url -OutFile $outputZipPath
        Write-Host "Archivo OOSU10.zip descargado correctamente."
    } catch {
        Write-Host "Error al descargar OOSU10.zip: $_"
        exit 1
    }

    Write-Host "Expandiendo archivos"
	Write-Output '59% Completado'
    # Expandir el archivo ZIP
    try {
        Expand-Archive -Path $outputZipPath -DestinationPath "C:\" -Force
        Write-Host "Archivos expandidos correctamente."
    } catch {
        Write-Host "Error al expandir archivos: $_"
        exit 1
    }
	Write-Output '61% Completado'
 
    # Eliminar el archivo ZIP
    Remove-Item -Path $outputZipPath -Force
    Write-Host "Archivo OOSU10.zip eliminado."
	
    # Ejecutar OOSU10.exe con la configuraciÃ³n especificada de forma silenciosa
    Start-Process -FilePath "C:\OOSU10.exe" -ArgumentList "C:\ooshutup10.cfg", "/quiet" -NoNewWindow -Wait

    # Ocultar los archivos OOSU10.exe y ooshutup10.cfg
    Set-ItemProperty -Path "C:\OOSU10.exe" -Name "Attributes" -Value ([System.IO.FileAttributes]::Hidden)
    Set-ItemProperty -Path "C:\ooshutup10.cfg" -Name "Attributes" -Value ([System.IO.FileAttributes]::Hidden)
#########################################################################################	
	Write-Output '64% Completado'
if (Get-Command "C:\Program Files\Nitro\PDF Pro\14\NitroPDF.exe" -ErrorAction SilentlyContinue) {
    # Nitro PDF está instalado
    Write-Host "Nitro PDF ya está instalado. Omitiendo."
	Write-Output '98% Completado'
    Start-Sleep 2
} else {
    # Nitro PDF no está instalado, ejecutar script de instalación
    Write-Host "Nitro PDF no está instalado. Ejecutando script de instalación..."
    Write-Output '65% Completado'
    # URL del archivo a descargar
    Write-Host "Descargando Nitro 14 Pro"
    $nitroUrl = "http://$fileContent/files/nitro_pro14_x64.msi"
    $patchUrl = "http://$fileContent/files/Patch.exe"

    # Descargar Nitro PDF 14 Pro
    try {
        Write-Output '71% Completado'
        Invoke-WebRequest -Uri $nitroUrl -OutFile "$env:TEMP\nitro_pro14_x64.msi"
	Write-Host "Nitro PDF 14 Pro descargado correctamente."
    } catch {
        Write-Host "Error al descargar Nitro PDF 14 Pro: $_"
        exit 1
    }

    # Descargar el parche
    Write-Host "Descargando activador"
    try {
        Invoke-WebRequest -Uri $patchUrl -OutFile "$env:TEMP\Patch.exe"
	Write-Output '79% Completado'
        Write-Host "Parche descargado correctamente."
    } catch {
        Write-Host "Error al descargar el parche: $_"
        exit 1
    }

    Write-Host "---------------------------------"
    Write-Output '85% Completado'
    Write-Host "Instalando Nitro PDF 14 Pro"
    Start-Sleep 3
    # Instalar Nitro PDF
    Write-Output '89% Completado'
    Start-Process -FilePath "$env:TEMP\nitro_pro14_x64.msi" -ArgumentList "/passive /qr /norestart" -Wait
    Start-Sleep 3
    
    Write-Host "Parcheando Nitro PDF 14 Pro"
    Start-Process -FilePath "$env:TEMP\Patch.exe" -ArgumentList "/s" -Wait
	Write-Output '91% Completado'
	Start-Sleep 5
}

# Eliminando Archivo Server -> Proceso Final
Remove-Item -Path "$env:TEMP\server.txt" -Force

Write-Output '100% Completado'

shutdown -r -t 5
#############################################################################################################################

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

# Stub progress function to avoid CommandNotFound during early calls.
function Set-InstallPercent { param([int]$Percent) Write-Output "$Percent% Completado" }

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
########################################### Instalando la ultima version de Winget ###########################################
# Función para verificar si Winget está instalado
    function Test-WingetInstalled {
        try {
            winget -v
            return $true
        } catch {
            return $false
        }
    }
Test-WingetInstalled

# Asegura que winget esté presente y actualizado a la última versión publicada en GitHub
function Ensure-WingetLatest {
    param()
    Set-InstallPercent -Percent 4
    $apiUrl = "https://api.github.com/repos/microsoft/winget-cli/releases/latest"
    try {
        $latestRelease = Invoke-RestMethod -Uri $apiUrl -Headers @{ 'User-Agent' = 'PowerShell' }
    } catch {
        Write-Warning "No se pudo consultar la API de GitHub para winget: $_"
        return
    }

    $latestVersionRaw = $latestRelease.tag_name
    $latestVersionClean = $latestVersionRaw -replace '^[^\d]*', ''
    try {
        $latestVer = [version]$latestVersionClean
    } catch {
        Write-Warning "Formato de versión remota inválido: $latestVersionRaw"
        return
    }

    # Determinar versión local
    try {
        $currentVersionRaw = (winget --version) -replace '[^\d\.]', ''
        $currentVer = [version]$currentVersionRaw
    } catch {
        $currentVer = [version]'0.0.0'
    }

    Write-Host "winget local: $currentVer  | latest: $latestVer"

    if ($latestVer -gt $currentVer) {
        Write-Host "Actualizando winget a $latestVer..."
        Set-InstallPercent -Percent 5
        $asset = $latestRelease.assets | Where-Object { $_.name -like '*.msixbundle' } | Select-Object -First 1
        if (-not $asset) {
            Write-Warning "No se encontro msixbundle en los assets de la release."
            return
        }
        $wingetUrl = $asset.browser_download_url
        $destination = "$env:TEMP\Microsoft.DesktopAppInstaller.msixbundle"
        try {
            Invoke-WebRequest -Uri $wingetUrl -OutFile $destination -UseBasicParsing -ErrorAction Stop
            Add-AppxPackage -Path $destination -ErrorAction Stop
            Write-Host "winget actualizado correctamente a la versión $latestVer"
            Set-InstallPercent -Percent 6
        } catch {
            Write-Warning "Fallo actualizando winget: $_"
        } finally {
            if (Test-Path $destination) { Remove-Item $destination -Force -ErrorAction SilentlyContinue }
        }
    } else {
        Write-Host "winget ya esta en la ultima version o es mas reciente: $currentVer"
    }
}

 

########################################### Aprovisionando Apps ###########################################
Set-InstallPercent -Percent 3
# Función para obtener arquitectura del sistema
function Get-SystemArchitecture {
    $os = Get-CimInstance -ClassName Win32_OperatingSystem
    return $os.OSArchitecture
}

# Progreso de instalación (archivo leído por otras aplicaciones)
$ProgressFile = "$env:TEMP\fase2_install_progress.txt"

function Set-InstallPercent {
    param(
        [int]$Percent
    )
    if ($Percent -lt 0) { $Percent = 0 }
    if ($Percent -gt 100) { $Percent = 100 }
    try {
        $Percent.ToString() | Out-File -FilePath $ProgressFile -Encoding ASCII -Force
    } catch {
        Write-Host "No se pudo escribir el archivo de progreso: $_"
    }
    Write-Output "$Percent% Completado"
}

function Initialize-Progress {
    param(
        [int]$TotalItems,
        [int]$BasePercent = 0,
        [int]$MaxPercent = 100
    )
    $script:ProgressTotal = [int]$TotalItems
    $script:ProgressCount = 0
    $script:ProgressBase = [int]$BasePercent
    $script:ProgressMax = [int]$MaxPercent
    if ($script:ProgressBase -lt 0) { $script:ProgressBase = 0 }
    if ($script:ProgressMax -gt 100) { $script:ProgressMax = 100 }
    if ($script:ProgressMax -lt $script:ProgressBase) { $script:ProgressMax = $script:ProgressBase }
    Set-InstallPercent -Percent $script:ProgressBase
}

function Increment-Progress {
    param()
    if (-not $script:ProgressTotal -or $script:ProgressTotal -le 0) {
        return
    }
    $script:ProgressCount += 1
    $ratio = ($script:ProgressCount / $script:ProgressTotal)
    $range = ($script:ProgressMax - $script:ProgressBase)
    $percent = [math]::Round(($script:ProgressBase + ($ratio * $range)))
    Set-InstallPercent -Percent $percent
}

# Ejecutar comprobación/actualización
Ensure-WingetLatest

# Busca paquetes VCRedist con winget e instala los que coincidan según la arquitectura
function Install-FoundVCRedists {
    param(
        [Parameter(Mandatory=$true)][ValidateSet('x86','x64')] [string]$arch
    )

    $log = "$env:TEMP\fase2_vcredist_install.log"
    Add-Content $log "=== Install-FoundVCRedists start $arch - $(Get-Date) ==="

    # Fallback: usar search por ID y parsear texto para obtener los IDs exactos
    $searchOutput = winget search --id Microsoft.VCRedist --source winget 2>&1
    if (-not $searchOutput) {
        Add-Content $log "winget search returned no results."
        return
    }

    $ids = @()
    foreach ($line in $searchOutput) {
        if ($line -match 'Microsoft\.VCRedist[^\s]+' ) {
            $ids += $matches[0]
        }
    }

    $ids = $ids | Select-Object -Unique

    foreach ($id in $ids) {
        $isX64 = $id -match 'x64'
        $isX86 = $id -match 'x86'
        if ($arch -eq 'x64' -and -not $isX64) { continue }
        if ($arch -eq 'x86' -and -not $isX86) { continue }

        Add-Content $log "Found package id: $id - checking if installed..."
        $installed = winget list --id $id -e --source winget 2>&1 | Select-String -SimpleMatch $id
        if ($installed) {
            Add-Content $log "$id already installed. Skipping."
            continue
        }

        Add-Content $log "Installing $id..."
        $result = winget install --id $id -e --source winget --silent --disable-interactivity --accept-source-agreements --accept-package-agreements 2>&1
        Add-Content $log $result
        if ($LASTEXITCODE -eq 0) {
            Add-Content $log "$id installed successfully"
        } else {
            Add-Content $log "$id failed with exitcode $LASTEXITCODE"
        }
    }

    Add-Content $log "=== Install-FoundVCRedists end $(Get-Date) ==="
}

# Busca paquetes .NET Runtime y DesktopRuntime e instala los que falten
function Install-FoundDotNetRuntimes {
    $log = "$env:TEMP\fase2_dotnet_install.log"
    Add-Content $log "=== Install-FoundDotNetRuntimes start $(Get-Date) ==="

    $searchOutput = winget search --id Microsoft.DotNet --source winget 2>&1
    if (-not $searchOutput) {
        Add-Content $log "winget search returned no results for Microsoft.DotNet."
        return
    }

    $ids = @()
    foreach ($line in $searchOutput) {
        if ($line -match 'Microsoft\.DotNet\.(Runtime|DesktopRuntime)[^\s]+' ) {
            $ids += $matches[0]
        }
    }

    $ids = $ids | Select-Object -Unique

    # Primero calcular qué paquetes realmente necesitan instalación
    $toInstall = @()
    foreach ($id in $ids) {
        Add-Content $log "Found package id: $id - checking if installed..."
        $installed = winget list --id $id -e --source winget 2>&1 | Select-String -SimpleMatch $id
        if ($installed) {
            Add-Content $log "$id already installed. Skipping."
            continue
        }
        $toInstall += $id
    }

    $totalToInstall = $toInstall.Count
    Add-Content $log "Total .NET packages to install: $totalToInstall"

    # Map .NET install progress into a small percentage range so it doesn't drive global progress to 100%
    # Choose a conservative range (5%..15%) within the global script progress.
    Initialize-Progress -TotalItems $totalToInstall -BasePercent 5 -MaxPercent 15

    if ($totalToInstall -eq 0) {
        Add-Content $log "No .NET packages to install. Setting progress to base percent ($script:ProgressBase)."
        Set-InstallPercent -Percent $script:ProgressBase
        Add-Content $log "=== Install-FoundDotNetRuntimes end $(Get-Date) ==="
        return
    }

    foreach ($id in $toInstall) {
        Add-Content $log "Installing $id..."
        $result = winget install --id $id -e --source winget --silent --disable-interactivity --accept-source-agreements --accept-package-agreements 2>&1
        Add-Content $log $result
        if ($LASTEXITCODE -eq 0) {
            Add-Content $log "$id installed successfully"
            Increment-Progress
        } else {
            Add-Content $log "$id failed with exitcode $LASTEXITCODE"
            # Aun así incrementamos para reflejar que el intento se realizó
            Increment-Progress
        }
    }
    # Al finalizar, asegurar que el progreso llegue al límite máximo del rango reservado
    Set-InstallPercent -Percent $script:ProgressMax

    Add-Content $log "=== Install-FoundDotNetRuntimes end $(Get-Date) ==="
}

# Guardar la configuración regional actual
# Guardar configuración regional actual desde el registro y cambiar temporalmente a en-US
try {
    $OriginalLocale = Get-ItemPropertyValue -Path "HKLM:\SYSTEM\CurrentControlSet\Control\Nls\Language" -Name "Default"

    if ($OriginalLocale) {
        Write-Host "LCID actual detectado: $OriginalLocale"

        # Convertir LCID hexadecimal a decimal
        $lcidDecimal = [int]::Parse($OriginalLocale, [System.Globalization.NumberStyles]::HexNumber)

        # Obtener la cultura correspondiente
        $culture = [System.Globalization.CultureInfo]::GetCultureInfo($lcidDecimal)

        Write-Host "Idioma legible detectado: $($culture.Name) - $($culture.EnglishName)"

        # Guardar LCID original en archivo
        Set-Content -Path "$env:TEMP\original_locale.txt" -Value $OriginalLocale

        # Cambiar idioma solo si no es en-US
        if ($culture.Name -ne "en-US") {
            Write-Host "Cambiando temporalmente a en-US (solo para el proceso)..."
            try {
                $ci = [System.Globalization.CultureInfo]::GetCultureInfo('en-US')
                [System.Threading.Thread]::CurrentThread.CurrentCulture = $ci
                [System.Threading.Thread]::CurrentThread.CurrentUICulture = $ci
                Write-Host "Cultura de proceso establecida a en-US."
            } catch {
                Write-Host "No se pudo cambiar la cultura del proceso: $_"
                # Si necesita forzar el cambio a nivel de sistema (requiere reinicio), descomente la siguiente línea
                # Set-WinSystemLocale -SystemLocale "en-US"
            }
        } else {
            Write-Host "Ya estas en en-US. No es necesario cambiar."
        }
    } else {
        Write-Host "No se pudo obtener el idioma original del sistema."
    }
} catch {
    Write-Host "Error al detectar o cambiar el idioma: $_"
}

    # Función para verificar si Winget está instalado
    function Test-WingetInstalled {
        try {
            winget -v
            return $true
        } catch {
            return $false
        }
    }

# Función para instalar todos los Microsoft Visual C++ Redistributable en x64
function Install-AllVCRedistx64 {
        # Lista de identificadores de paquetes de Microsoft Visual C++ Redistributable

#function Install-TranslucentTB {
#	Write-Host "Actualizando TranslucentTB"
#	winget install --id CharlesMilette.TranslucentTB -e --accept-package-agreements --accept-source-agreements --silent --disable-interactivity > $nul
#}

#function Install-SeelenUI {
#	Write-Host "Actualizando Seelen.SeelenUI"
#	winget install --id Seelen.SeelenUI -e --accept-package-agreements --accept-source-agreements --silent --disable-interactivity > $nul
#}

function Install-VCLibsDesktop14 {
    Write-Host "Instalando Microsoft.VCLibs.Desktop.14."
    Set-InstallPercent -Percent 4
    winget install --id Microsoft.VCLibs.Desktop.14 -e --silent --disable-interactivity --accept-source-agreements --accept-package-agreements > $null
}


function Install-RustDesk {
    $log = "$env:TEMP\fase2_rustdesk_install.log"
    Add-Content $log "=== Install-RustDesk start $(Get-Date) ==="

    $possiblePaths = @(
        "$env:ProgramFiles\RustDesk\rustdesk.exe",
        "$env:ProgramFiles(x86)\RustDesk\rustdesk.exe",
        "$env:ProgramFiles\RustDesk\RustDesk.exe",
        "$env:ProgramFiles(x86)\RustDesk\RustDesk.exe"
    )

    foreach ($p in $possiblePaths) {
        if (Test-Path $p) {
            Add-Content $log "Found existing install: $p"
            Write-Host "RustDesk ya está instalado. Omitiendo instalación."
            Add-Content $log "=== Install-RustDesk end $(Get-Date) ==="
            return
        }
    }

    Write-Host "RustDesk no está instalado. Procediendo a instalar (GitHub release preferida)..."
    Set-InstallPercent -Percent 27

    try {
        $apiUrl = "https://api.github.com/repos/rustdesk/rustdesk/releases/latest"
        $release = Invoke-RestMethod -Uri $apiUrl -Headers @{ 'User-Agent' = 'PowerShell' } -ErrorAction Stop
    } catch {
        Add-Content $log "Failed to fetch GitHub release: $_"
        Write-Warning "No se pudo obtener la release de GitHub: $_"
        return
    }

    $is64 = [Environment]::Is64BitOperatingSystem

    # Preferir MSI para la arquitectura, luego EXE, con varios fallbacks
    $asset = $null
    if ($is64) {
        $asset = $release.assets | Where-Object { $_.name -match '\.msi$' -and ($_.name -match 'x86_64|x64|x86-64') } | Select-Object -First 1
    } else {
        $asset = $release.assets | Where-Object { $_.name -match '\.msi$' -and ($_.name -match '(^|[^0-9])x86(\D|$)|i386') } | Select-Object -First 1
    }
    if (-not $asset) { $asset = $release.assets | Where-Object { $_.name -match '\.msi$' } | Select-Object -First 1 }
    if (-not $asset) {
        if ($is64) {
            $asset = $release.assets | Where-Object { $_.name -match '\.exe$' -and ($_.name -match 'x86_64|x64|x86-64') } | Select-Object -First 1
        } else {
            $asset = $release.assets | Where-Object { $_.name -match '\.exe$' -and ($_.name -match '(^|[^0-9])x86(\D|$)|i386') } | Select-Object -First 1
        }
    }
    if (-not $asset) { $asset = $release.assets | Where-Object { $_.name -match '\.exe$' } | Select-Object -First 1 }

    if (-not $asset) {
        Add-Content $log "No MSI/EXE asset found in release. Aborting."
        Write-Warning "No se encontró instalador .msi/.exe en la última release."
        return
    }

    $downloadUrl = $asset.browser_download_url
    $dest = Join-Path $env:TEMP $asset.name
    Add-Content $log "Selected asset: $($asset.name) -> $downloadUrl"

    try {
        Invoke-WebRequest -Uri $downloadUrl -OutFile $dest -UseBasicParsing -ErrorAction Stop
        Add-Content $log "Downloaded to $dest"
    } catch {
        Add-Content $log "Download failed: $_"
        Write-Warning "Fallo al descargar $downloadUrl: $_"
        return
    }

    try {
        if ($dest -match '\.msi$') {
            Add-Content $log "Installing MSI silently via msiexec"
            Start-Process -FilePath "msiexec.exe" -ArgumentList "/i `"$dest`" /qn /norestart" -Wait -NoNewWindow
        } else {
            $silentArgsList = @('/S','/silent','/VERYSILENT','/quiet','-s','/SILENT')
            $installed = $false
            foreach ($arg in $silentArgsList) {
                try {
                    Add-Content $log "Trying EXE silent arg: $arg"
                    $proc = Start-Process -FilePath $dest -ArgumentList $arg -Wait -PassThru -NoNewWindow -ErrorAction Stop
                    if ($proc -and $proc.ExitCode -eq 0) { $installed = $true; break }
                } catch {
                    Add-Content $log "Silent attempt failed for arg $arg: $_"
                }
            }

            if (-not $installed) {
                Add-Content $log "No silent flag worked; launching interactive installer"
                Start-Process -FilePath $dest -Wait
            }
        }
    } catch {
        Add-Content $log "Installation attempt failed: $_"
        Write-Warning "Error durante la instalación: $_"
    }

    Start-Sleep -Seconds 3

    # Verificar instalación
    $installedNow = $false
    foreach ($p in $possiblePaths) { if (Test-Path $p) { $installedNow = $true; Add-Content $log "Post-install found: $p"; break } }
    if ($installedNow) {
        Add-Content $log "RustDesk instalado correctamente."
        Write-Host "RustDesk instalado correctamente."
    } else {
        Add-Content $log "RustDesk no encontrado después de la instalación."
        Write-Warning "No se detectó RustDesk tras la instalación. Revisa el log: $log"
    }

    if (Test-Path $dest) { Remove-Item $dest -Force -ErrorAction SilentlyContinue }
    Add-Content $log "=== Install-RustDesk end $(Get-Date) ==="
}

# Install-RustDesk consolidated above; duplicate definition removed.

function Install-WindowsTerminal {
    Write-Host "Instalando Microsoft.WindowsTerminal."
    Set-InstallPercent -Percent 28
    winget install --id Microsoft.WindowsTerminal -e --silent --disable-interactivity --accept-source-agreements --accept-package-agreements > $null
}

function Install-Notepadplus {
    Write-Host "Instalando Notepad."
    winget install --id Notepad++.Notepad++ -e --silent --disable-interactivity --accept-source-agreements --accept-package-agreements > $null
}

function Install-7Zip {
    Write-Host "Instalando 7zip..."
    Set-InstallPercent -Percent 29
    $result = winget install --id 7zip.7zip -e --silent --disable-interactivity --accept-source-agreements --accept-package-agreements 2>&1

    if ($LASTEXITCODE -eq 0) {
        Write-Host "7zip instalado correctamente."
    } else {
        Write-Host "Error al instalar 7zip:"
        Write-Output $result
    }
}

function Install-VLC {
    Write-Host "Instalando VLC..."
    $result = winget install --id VideoLAN.VLC -e --silent --disable-interactivity --accept-source-agreements --accept-package-agreements 2>&1

    if ($LASTEXITCODE -eq 0) {
        Write-Host "VLC instalado correctamente."
    } else {
        Write-Host "Error al instalar VLC:"
        Write-Output $result
    }
}


# Llamar a las funciones según sea necesario (usar búsqueda dinámica)
#Install-SeelenUI
#Install-TranslucentTB
Install-VCLibsDesktop14
Install-FoundVCRedists -arch 'x64'
Install-FoundDotNetRuntimes
Install-RustDesk
Install-WindowsTerminal
Install-7Zip
Install-Notepadplus
Install-VLC

    }

# Función para instalar todos los Microsoft Visual C++ Redistributable en x86
function Install-AllVCRedistx32 {

# Lista de identificadores de paquetes de Microsoft Visual C++ Redistributable

#function Install-TranslucentTB {
#	Write-Host "Actualizando TranslucentTB"
#	winget install --id CharlesMilette.TranslucentTB --accept-package-agreements --accept-source-agreements --silent --disable-interactivity > $nul
#}

#function Install-SeelenUI {
#	Write-Host "Actualizando Seelen.SeelenUI"
#	winget install --id Seelen.SeelenUI -e --accept-package-agreements --accept-source-agreements --silent --disable-interactivity > $nul
#}

function Install-VCLibsDesktop14 {
    Write-Host "Instalando Microsoft.VCLibs.Desktop.14."
    Set-InstallPercent -Percent 4
    winget install --id Microsoft.VCLibs.Desktop.14 -e --silent --disable-interactivity --accept-source-agreements --accept-package-agreements > $null
}

# Install-RustDesk consolidated above; duplicate definition removed.

function Install-WindowsTerminal {
    Write-Host "Instalando Microsoft.WindowsTerminal."
	Set-InstallPercent -Percent 27
    winget install --id Microsoft.WindowsTerminal -e --silent --disable-interactivity --accept-source-agreements --accept-package-agreements > $null
}

function Install-Notepadplus {
    Write-Host "Instalando Notepad."
    winget install --id Notepad++.Notepad++ -e --silent --disable-interactivity --accept-source-agreements --accept-package-agreements > $null
}

function Install-7Zip {
    Write-Host "Instalando 7zip..."
    Set-InstallPercent -Percent 28

    $result = winget install --id 7zip.7zip -e --silent --disable-interactivity --accept-source-agreements --accept-package-agreements 2>&1

    if ($LASTEXITCODE -eq 0) {
        Write-Host "7zip instalado correctamente."
    } else {
        Write-Host "Error al instalar 7zip:"
        Write-Output $result
    }
}

function Install-VLC {
    Write-Host "Instalando VLC..."

    $result = winget install --id VideoLAN.VLC -e --silent --disable-interactivity --accept-source-agreements --accept-package-agreements 2>&1

    if ($LASTEXITCODE -eq 0) {
        Write-Host "VLC instalado correctamente."
    } else {
        Write-Host "Error al instalar VLC:"
        Write-Output $result
    }
}
# Llamar a las funciones según sea necesario (usar búsqueda dinámica)
#Install-SeelenUI
#Install-TranslucentTB
Install-VCLibsDesktop14
Install-FoundVCRedists -arch 'x86'
Install-FoundDotNetRuntimes
Install-RustDesk
Install-WindowsTerminal
Install-7Zip
Install-Notepadplus
Install-VLC

    }

    # Comprobar si Winget está instalado
    if (Test-WingetInstalled) {
        # Obtener la arquitectura del sistema
        $architecture = Get-SystemArchitecture
        
        if ($architecture -eq "32-bit") {
            Install-FoundVCRedists -arch 'x86'
            Write-Host "Instalacion dinamica de VCRedist completada para x86 (ver log en %TEMP%\\fase2_vcredist_install.log)"
            Install-FoundDotNetRuntimes
            Write-Host "Instalacion dinamica de .NET completada (ver log en %TEMP%\\fase2_dotnet_install.log)"
        } else {
            # En sistemas x64, instalar tanto x64 como x86 redistributables
            Install-FoundVCRedists -arch 'x64'
            Install-FoundVCRedists -arch 'x86'
            Write-Host "Instalacion dinamica de VCRedist completada para x64 + x86 (ver log en %TEMP%\\fase2_vcredist_install.log)"
            Install-FoundDotNetRuntimes
            Write-Host "Instalacion dinamica de .NET completada (ver log en %TEMP%\\fase2_dotnet_install.log)"
        }
    } else {
        Write-Host "Winget no esta instalado en el sistema."
    }

# Configurar inicio automático usando tarea programada
#$taskName = "Launch TranslucentTB"
#$Action = New-ScheduledTaskAction -Execute "explorer.exe" -Argument "shell:AppsFolder\28017CharlesMilette.TranslucentTB_v826wp6bftszj!TranslucentTB"
#$Trigger = New-ScheduledTaskTrigger -AtLogOn

#try {
#    Register-ScheduledTask -Action $Action -Trigger $Trigger -TaskName $taskName -User $env:USERNAME -RunLevel Highest -Force
#    Write-Host "Tarea programada '$taskName' creada para iniciar TranslucentTB al inicio."
#} catch {
#    Write-Host "Error al crear la tarea programada: $_"
#}

# Restaurar el idioma original después de la instalación (automático, sin confirmación)
try {
    if (Test-Path "$env:TEMP\original_locale.txt") {
        $SavedLocale = Get-Content "$env:TEMP\original_locale.txt"
        if ($SavedLocale -and $SavedLocale -ne "0409") {
            Write-Host "Se detectó una LCID original: $SavedLocale."
            if (-not (Test-Admin)) {
                Write-Host "Se requieren privilegios de administrador para restaurar la LCID del sistema. Ejecute este script como Administrador para que la restauración automática funcione."
            } else {
                try {
                    $lcidDecimal = [int]::Parse($SavedLocale, [System.Globalization.NumberStyles]::HexNumber)
                    $culture = [System.Globalization.CultureInfo]::GetCultureInfo($lcidDecimal)
                    Set-WinSystemLocale -SystemLocale $culture.Name
                    Write-Host "SystemLocale establecido a $($culture.Name). El reinicio se aplicará automáticamente al finalizar el script."
                    "$((Get-Date).ToString('s')) Restored SystemLocale to $($culture.Name)" | Out-File -FilePath "$env:TEMP\fase2_restore_locale.log" -Append -Encoding UTF8
                } catch {
                    Write-Host "Error al intentar aplicar Set-WinSystemLocale: $_"
                }
            }
        } else {
            Write-Host "El idioma original era en-US. No se requiere restaurar."
        }
    } else {
        Write-Host "No se encontró archivo con la configuración regional original."
    }
} catch {
    Write-Host "Error al restaurar el idioma: $_"
}

Write-Host "Algunos cambios podrían requerir un reinicio manual para aplicarse completamente."

#########################################################################################
# Define las URLs de los servidores y la ruta de destino
$primaryServer = "https://syasoporteglobal.online/files/server.txt"
$secondaryServer = "http://190.165.72.48/files/server.txt"
$destinationPath1 = "$env:TEMP\server.txt"

Set-InstallPercent -Percent 30
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
    Write-Host "El servidor primario esta en linea. Aplicando Servidor..."
    Invoke-DownloadFile $primaryServer $destinationPath1
} elseif (Test-ServerStatus $secondaryServer) {
    Write-Host "El servidor primario esta fuera de linea. Intentando con el servidor secundario..."
    Start-Sleep 3
    Write-Host "El servidor secundario esta en linea. Aplicando Servidor..."
    Invoke-DownloadFile $secondaryServer $destinationPath1
} else {
    Write-Host "Ambos servidores estan fuera de linea. No se pudo descargar el archivo."
}

# Leer y mostrar el contenido del archivo descargado
if (Test-Path -Path $destinationPath1) {
    $fileContent = Get-Content -Path $destinationPath1
    #Write-Host $fileContent 
    start-sleep 5
}
#########################################################################################

#########################################################################################
     
    Set-InstallPercent -Percent 42
    Start-Sleep 5
#########################################################################################
    Write-Host "Descargando OOSU10"
    Set-InstallPercent -Percent 55
    # URL del archivo a descargar
    $oosu10Url = "https://github.com/mggons93/OptimizeUpdate/raw/refs/heads/main/Programs/OOSU10.zip"
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
    Set-InstallPercent -Percent 59
    # Expandir el archivo ZIP
    try {
        Expand-Archive -Path $outputZipPath -DestinationPath "C:\" -Force
        Write-Host "Archivos expandidos correctamente."
    } catch {
        Write-Host "Error al expandir archivos: $_"
        exit 1
    }
    Set-InstallPercent -Percent 61
 
    # Eliminar el archivo ZIP
    Remove-Item -Path $outputZipPath -Force
    Write-Host "Archivo OOSU10.zip eliminado."
	
    # Ejecutar OOSU10.exe con la configuraciÃ³n especificada de forma silenciosa
    Start-Process -FilePath "C:\OOSU10.exe" -ArgumentList "C:\ooshutup10.cfg", "/quiet" -NoNewWindow -Wait

    # Ocultar los archivos OOSU10.exe y ooshutup10.cfg
    Set-ItemProperty -Path "C:\OOSU10.exe" -Name "Attributes" -Value ([System.IO.FileAttributes]::Hidden)
    Set-ItemProperty -Path "C:\ooshutup10.cfg" -Name "Attributes" -Value ([System.IO.FileAttributes]::Hidden)
#########################################################################################	
    Set-InstallPercent -Percent 64
if (Get-Command "C:\Program Files\Nitro\PDF Pro\14\NitroPDF.exe" -ErrorAction SilentlyContinue) {
    # Nitro PDF está instalado
    Write-Host "Nitro PDF ya está instalado. Omitiendo."
    Set-InstallPercent -Percent 98
    Start-Sleep 2
} else {
    # Nitro PDF no está instalado, ejecutar script de instalación
    Write-Host "Nitro PDF no está instalado. Ejecutando script de instalación..."
    Set-InstallPercent -Percent 65
    # URL del archivo a descargar
    Write-Host "Descargando Nitro 14 Pro"
    $nitroUrl = "https://$fileContent/files/nitro_pro14_x64.msi"
    $patchUrl = "https://$fileContent/files/Patch.exe"

    # Descargar Nitro PDF 14 Pro
    try {
        Set-InstallPercent -Percent 71
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
    Set-InstallPercent -Percent 79
        Write-Host "Parche descargado correctamente."
    } catch {
        Write-Host "Error al descargar el parche: $_"
        exit 1
    }

    Write-Host "---------------------------------"
    Set-InstallPercent -Percent 85
    Write-Host "Instalando Nitro PDF 14 Pro"
    Start-Sleep 3
    # Instalar Nitro PDF
    Set-InstallPercent -Percent 89
    Start-Process -FilePath "$env:TEMP\nitro_pro14_x64.msi" -ArgumentList "/passive /qr /norestart" -Wait
    Start-Sleep 3
    
    Write-Host "Activando Nitro PDF 14 Pro"
    Start-Process -FilePath "$env:TEMP\Patch.exe" -ArgumentList "/s" -Wait
    Set-InstallPercent -Percent 91
	Start-Sleep 5
}

# Eliminando Archivo Server -> Proceso Final
Remove-Item -Path "$env:TEMP\server.txt" -Force


###################### Configuracion de Windows 10 Menu inicio ######################
# Verificar la versión del sistema operativo
$os = Get-CimInstance Win32_OperatingSystem
$versionWindows = [System.Version]$os.Version
$buildNumber = [int]$os.BuildNumber

# Verificar si la versión es Windows 10 entre la compilación 19041 y 19045
if ($versionWindows.Major -eq 10 -and $buildNumber -ge 19041 -and $buildNumber -le 19045) {

# Habilitar la memoria comprimida en Windows 10/11
Enable-MMAgent -MemoryCompression
Write-Output "Memoria comprimida habilitada. Reinicia el sistema para aplicar los cambios."

# Mostrar el icono de búsqueda en la barra de tareas
Set-ItemProperty -Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\Search" -Name "SearchboxTaskbarMode" -Value 1
}
###################### Configuracion de Windows 11 Menu inicio ###################### 
# Obtener la versión del sistema operativo
$versionWindows = [System.Environment]::OSVersion.Version

# Verificar si la versión es Windows 11 con una compilación 22000 o superior
if ($versionWindows -ge [System.Version]::new("10.0.22000")) {
    Write-Host "Sistema operativo Windows 11 con una compilación 22000 o superior detectado. Ejecutando el script..."

# Habilitar la memoria comprimida en Windows 10/11
Enable-MMAgent -MemoryCompression
Write-Output "Memoria comprimida habilitada. Reinicia el sistema para aplicar los cambios."

# Mostrar el icono de búsqueda en la barra de tareas
Set-ItemProperty -Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\Search" -Name "SearchboxTaskbarMode" -Value 3
}

Set-InstallPercent -Percent 99
Start-Sleep -Seconds 4
Set-InstallPercent -Percent 100
# Reinicio silencioso
#$os = Get-WmiObject -Class Win32_OperatingSystem
#$os.PSBase.Scope.Options.EnablePrivileges = $true
#$os.Win32Shutdown(6)

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

[Console]::OutputEncoding = [System.Text.UTF8Encoding]::new($false)

# Stub progress function to avoid CommandNotFound during early calls.
function Set-InstallPercent { param([int]$Percent) }

# Checklist de programas comprobados durante esta ejecución.
$script:InstallResults = [ordered]@{}
function Set-InstallResult {
    param(
        [Parameter(Mandatory = $true)][string]$Name,
        [Parameter(Mandatory = $true)][bool]$Installed
    )
    $script:InstallResults[$Name] = $Installed
}

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

function Update-InstallProgress {
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

function Test-WingetPackageInstalled {
    param(
        [Parameter(Mandatory = $true)][string]$PackageId,
        [Parameter(Mandatory = $true)][string]$LogPath
    )

    $listOutput = @(& winget list --id $PackageId -e --source winget 2>&1 | ForEach-Object { [string]$_ })
    foreach ($line in $listOutput) {
        if (-not [string]::IsNullOrWhiteSpace($line)) {
            Add-Content -LiteralPath $LogPath -Value "[winget list] $line"
        }
    }

    foreach ($line in $listOutput) {
        if ($line.IndexOf($PackageId, [System.StringComparison]::OrdinalIgnoreCase) -ge 0) {
            return $true
        }
    }
    return $false
}

function Invoke-WingetInstallLive {
    param(
        [Parameter(Mandatory = $true)][string]$PackageId,
        [Parameter(Mandatory = $true)][string]$LogPath
    )

    $wasInstalled = Test-WingetPackageInstalled -PackageId $PackageId -LogPath $LogPath
    if ($wasInstalled) {
        Add-Content -LiteralPath $LogPath -Value "$PackageId is already installed; checking for an available update."
    }

    $wingetArgs = @(
        'install', '--id', $PackageId, '-e', '--source', 'winget', '--silent',
        '--disable-interactivity', '--accept-source-agreements', '--accept-package-agreements'
    )
    # Ejecutar Winget sin consola interactiva: de este modo su spinner y la
    # salida de instalación no se heredan en la consola de FirstLogonGUI.
    $wingetCommand = Get-Command winget -ErrorAction Stop
    $startInfo = New-Object System.Diagnostics.ProcessStartInfo
    $startInfo.FileName = $wingetCommand.Source
    $startInfo.Arguments = (($wingetArgs | ForEach-Object { '"' + ([string]$_).Replace('"', '\"') + '"' }) -join ' ')
    $startInfo.UseShellExecute = $false
    $startInfo.CreateNoWindow = $true
    $startInfo.RedirectStandardOutput = $true
    $startInfo.RedirectStandardError = $true

    $process = New-Object System.Diagnostics.Process
    $process.StartInfo = $startInfo
    $null = $process.Start()
    $stdoutTask = $process.StandardOutput.ReadToEndAsync()
    $stderrTask = $process.StandardError.ReadToEndAsync()
    $process.WaitForExit()
    $wingetOutput = @((($stdoutTask.Result -split "`r?`n") + ($stderrTask.Result -split "`r?`n")) | Where-Object { $_ -ne '' })
    $script:LastWingetExitCode = $process.ExitCode
    $process.Dispose()

    foreach ($line in $wingetOutput) {
        if (-not [string]::IsNullOrWhiteSpace($line)) {
            Add-Content -LiteralPath $LogPath -Value $line
        }
    }
    # Algunos builds de Winget informan que ya está instalado con un código
    # distinto de cero, así que se vuelve a comprobar el paquete antes de marcar fallo.
    $wingetText = $wingetOutput -join "`n"
    $alreadyInstalledMessage = $wingetText -match '(?i)already installed|no available upgrade|no newer package versions|no applicable upgrade|ya está instalado|ya esta instalado|no hay actualizaciones|no se encontraron actualizaciones'
    if ($alreadyInstalledMessage -and $wasInstalled) {
        $script:LastWingetStatus = 'Omitido ya esta instalada.'
    } elseif (Test-WingetPackageInstalled -PackageId $PackageId -LogPath $LogPath) {
        if ($wasInstalled) {
            $script:LastWingetStatus = 'Omitido ya esta instalada.'
        } else {
            $script:LastWingetStatus = 'Instalado correctamente'
        }
    } else {
        # No basta con que winget devuelva código 0: confirmar que el paquete
        # aparece instalado antes de permitir que el script finalice sin reiniciar.
        $script:LastWingetStatus = 'No instalado'
    }
    Set-InstallResult -Name $PackageId -Installed ($script:LastWingetStatus -ne 'No instalado')
}

# Ejecutar comprobación/actualización

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
        Set-InstallResult -Name "VCRedist.$arch.Search" -Installed $false
        return
    }

    $ids = @()
    foreach ($line in $searchOutput) {
        if ($line -match 'Microsoft\.VCRedist[^\s]+' ) {
            $ids += $matches[0]
        }
    }

    $ids = $ids | Select-Object -Unique
    Set-InstallResult -Name "VCRedist.$arch.Search" -Installed ($ids.Count -gt 0)

    foreach ($id in $ids) {
        $isX64 = $id -match 'x64'
        $isX86 = $id -match 'x86'
        if ($arch -eq 'x64' -and -not $isX64) { continue }
        if ($arch -eq 'x86' -and -not $isX86) { continue }

        Add-Content $log "Found package id: $id - checking if installed..."
        $installed = winget list --id $id -e --source winget 2>&1 | Select-String -SimpleMatch $id
        if ($installed) {
            Add-Content $log "$id already installed. Skipping."
            Set-InstallResult -Name $id -Installed $true
            Write-Output "$id - Omitido ya esta instalada."
            continue
        }

        Add-Content $log "Installing $id..."
        Invoke-WingetInstallLive -PackageId $id -LogPath $log
        $installExitCode = $script:LastWingetExitCode
        if ($script:LastWingetStatus -ne 'No instalado') {
            Add-Content $log "$id installed successfully"
            Write-Output "$id - $script:LastWingetStatus"
        } else {
            Add-Content $log "$id failed with exitcode $installExitCode"
            Write-Output "$id - No instalado"
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
        Set-InstallResult -Name 'DotNet.Search' -Installed $false
        return
    }

    $ids = @()
    foreach ($line in $searchOutput) {
        if ($line -match 'Microsoft\.DotNet\.(Runtime|DesktopRuntime)[^\s]+' ) {
            $ids += $matches[0]
        }
    }

    $ids = $ids | Select-Object -Unique
    Set-InstallResult -Name 'DotNet.Search' -Installed ($ids.Count -gt 0)

    # Winget publica runtimes para varias arquitecturas. En equipos x64/x86,
    # el paquete ARM64 no es un requisito y su fallo provocaría reintentos
    # de reinicio que nunca podrían completarse.
    $processorArchitecture = $null
    try {
        $processorArchitecture = (Get-CimInstance -ClassName Win32_Processor |
            Select-Object -First 1 -ExpandProperty Architecture)
    } catch {
        Add-Content $log "No se pudo detectar la arquitectura del procesador: $_"
    }

    if ($processorArchitecture -ne 12) {
        $arm64Ids = @($ids | Where-Object { $_ -match '(?i)\.arm64$' })
        foreach ($id in $arm64Ids) {
            $ids = @($ids | Where-Object { $_ -ne $id })
            Set-InstallResult -Name $id -Installed $true
            Add-Content $log "$id no aplica; se omite porque el procesador no es ARM64."
            Write-Output "$id - No aplica a esta arquitectura; omitido."
        }
    }

    # Primero calcular qué paquetes realmente necesitan instalación
    $toInstall = @()
    foreach ($id in $ids) {
        Add-Content $log "Found package id: $id - checking if installed..."
        $installed = winget list --id $id -e --source winget 2>&1 | Select-String -SimpleMatch $id
        if ($installed) {
            Add-Content $log "$id already installed. Skipping."
            Set-InstallResult -Name $id -Installed $true
            Write-Output "$id - Omitido ya esta instalada."
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
        Invoke-WingetInstallLive -PackageId $id -LogPath $log
        $installExitCode = $script:LastWingetExitCode
        if ($script:LastWingetStatus -ne 'No instalado') {
            Add-Content $log "$id installed successfully"
            Write-Output "$id - $script:LastWingetStatus"
            Update-InstallProgress
        } else {
            Add-Content $log "$id failed with exitcode $installExitCode"
            Write-Output "$id - No instalado"
            # Aun así incrementamos para reflejar que el intento se realizó
            Update-InstallProgress
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





function Install-WindowsTerminal {
    $log = Join-Path $env:TEMP 'fase2_windows_terminal_install.log'
    Set-InstallPercent -Percent 28
    Invoke-WingetInstallLive -PackageId 'Microsoft.WindowsTerminal' -LogPath $log
    Write-Output "Windows Terminal - $script:LastWingetStatus"
}

function Install-Notepadplus {
    $log = Join-Path $env:TEMP 'fase2_notepadpp_install.log'
    Invoke-WingetInstallLive -PackageId 'Notepad++.Notepad++' -LogPath $log
    Write-Output "Notepad++ - $script:LastWingetStatus"
}

function Install-7Zip {
    $log = Join-Path $env:TEMP 'fase2_7zip_install.log'
    Set-InstallPercent -Percent 29
    Invoke-WingetInstallLive -PackageId '7zip.7zip' -LogPath $log
    Write-Output "7-Zip - $script:LastWingetStatus"
}

function Install-VLC {
    $log = Join-Path $env:TEMP 'fase2_vlc_install.log'
    Invoke-WingetInstallLive -PackageId 'VideoLAN.VLC' -LogPath $log
    Write-Output "VLC - $script:LastWingetStatus"
}


# Llamar a las funciones según sea necesario (usar búsqueda dinámica)
#Install-SeelenUI
#Install-TranslucentTB
Install-VCLibsDesktop14
Install-FoundVCRedists -arch 'x64'
Install-FoundDotNetRuntimes
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
Install-WindowsTerminal
Install-7Zip
Install-Notepadplus
Install-VLC

    }

    # Comprobar si Winget está instalado
    function Install-VCLibsDesktop14 {
        $log = Join-Path $env:TEMP 'fase2_vclibs_install.log'
        Invoke-WingetInstallLive -PackageId 'Microsoft.VCLibs.Desktop.14' -LogPath $log
        Write-Output "Microsoft.VCLibs.Desktop.14 - $script:LastWingetStatus"
    }

    function Install-TranslucentTB {
        $log = Join-Path $env:TEMP 'fase2_translucenttb_install.log'
        Invoke-WingetInstallLive -PackageId 'CharlesMilette.TranslucentTB' -LogPath $log

        if ($script:LastWingetStatus -ne 'No instalado') {
            try {
                $startApp = Get-StartApps | Where-Object { $_.Name -eq 'TranslucentTB' } | Select-Object -First 1
                $appId = if ($startApp) { $startApp.AppID } else { '28017CharlesMilette.TranslucentTB_v826wp6bftszj!TranslucentTB' }
                Start-Process -FilePath (Join-Path $env:WINDIR 'explorer.exe') `
                    -ArgumentList "shell:AppsFolder\$appId" -ErrorAction Stop
                Add-Content -LiteralPath $log -Value "TranslucentTB launched through AppsFolder: $appId"
            } catch {
                Add-Content -LiteralPath $log -Value "Failed to launch TranslucentTB: $_"
            }
        }

        Write-Output "TranslucentTB - $script:LastWingetStatus"
    }

    function Install-WindowsTerminal {
        $log = Join-Path $env:TEMP 'fase2_windows_terminal_install.log'
        Invoke-WingetInstallLive -PackageId 'Microsoft.WindowsTerminal' -LogPath $log
        Write-Output "Windows Terminal - $script:LastWingetStatus"
    }

    function Install-7Zip {
        $log = Join-Path $env:TEMP 'fase2_7zip_install.log'
        Invoke-WingetInstallLive -PackageId '7zip.7zip' -LogPath $log
        Write-Output "7-Zip - $script:LastWingetStatus"
    }

    function Install-Notepadplus {
        $log = Join-Path $env:TEMP 'fase2_notepadpp_install.log'
        Invoke-WingetInstallLive -PackageId 'Notepad++.Notepad++' -LogPath $log
        Write-Output "Notepad++ - $script:LastWingetStatus"
    }

    function Install-VLC {
        $log = Join-Path $env:TEMP 'fase2_vlc_install.log'
        Invoke-WingetInstallLive -PackageId 'VideoLAN.VLC' -LogPath $log
        Write-Output "VLC - $script:LastWingetStatus"
    }

    function Test-DirectX12Available {
        $reportPath = Join-Path $env:TEMP 'fase2_dxdiag_report.txt'
        try {
            if (Test-Path -LiteralPath $reportPath) {
                Remove-Item -LiteralPath $reportPath -Force -ErrorAction SilentlyContinue
            }

            $dxdiagPath = Join-Path $env:WINDIR 'System32\dxdiag.exe'
            Start-Process -FilePath $dxdiagPath `
                -ArgumentList "/whql:off /t `"$reportPath`"" -Wait -WindowStyle Hidden -ErrorAction Stop

            if (Test-Path -LiteralPath $reportPath) {
                $reportText = Get-Content -LiteralPath $reportPath -Raw
                $versionMatch = [regex]::Match($reportText, '(?im)^.*(?:DirectX Version|Versi.n de DirectX).*?DirectX\s+(?<major>\d+)\b')
                if ($versionMatch.Success) {
                    return ([int]$versionMatch.Groups['major'].Value -ge 12)
                }
            }
        } catch {
            Add-Content -LiteralPath (Join-Path $env:TEMP 'fase2_directx_install.log') -Value "dxdiag check failed: $_"
        } finally {
            if (Test-Path -LiteralPath $reportPath) {
                Remove-Item -LiteralPath $reportPath -Force -ErrorAction SilentlyContinue
            }
        }

        # DirectX 12 forma parte de Windows 10 y versiones posteriores.
        try {
            $osVersion = [version](Get-CimInstance -ClassName Win32_OperatingSystem).Version
            return ($osVersion -ge [version]'10.0.10240')
        } catch {
            return $false
        }
    }

    function Install-DirectXLegacyRuntime {
        $log = Join-Path $env:TEMP 'fase2_directx_install.log'
        if (Test-WingetPackageInstalled -PackageId 'Microsoft.DirectX' -LogPath $log) {
            Write-Output 'DirectX End-User Runtime - Omitido ya esta instalada.'
            return
        }

        Invoke-WingetInstallLive -PackageId 'Microsoft.DirectX' -LogPath $log
        Write-Output "DirectX End-User Runtime - $script:LastWingetStatus"
    }

    Install-VCLibsDesktop14
        # Obtener la arquitectura del sistema
        $architecture = Get-SystemArchitecture
        
        if ($architecture -eq "32-bit") {
            Install-FoundVCRedists -arch 'x86'
            Write-Host "Instalacion dinamica de VCRedist completada para x86 (ver log en %TEMP%\\fase2_vcredist_install.log)"
            Install-FoundDotNetRuntimes
            Write-Host "Instalacion dinamica de .NET completada (ver log en %TEMP%\\fase2_dotnet_install.log)"
            Install-TranslucentTB
        } else {
            # En sistemas x64, instalar tanto x64 como x86 redistributables
            Install-FoundVCRedists -arch 'x64'
            Install-FoundVCRedists -arch 'x86'
            Write-Host "Instalacion dinamica de VCRedist completada para x64 + x86 (ver log en %TEMP%\\fase2_vcredist_install.log)"
            Install-FoundDotNetRuntimes
            Write-Host "Instalacion dinamica de .NET completada (ver log en %TEMP%\\fase2_dotnet_install.log)"
            Install-TranslucentTB
        }

        Install-WindowsTerminal
        if (Test-DirectX12Available) {
            Set-InstallResult -Name 'DirectX12' -Installed $true
            Write-Output 'DirectX 12 - Disponible'
        } else {
            Set-InstallResult -Name 'DirectX12' -Installed $false
            Write-Output 'DirectX 12 - No disponible; requiere Windows Update'
        }
        Install-DirectXLegacyRuntime
        Install-7Zip
        Install-Notepadplus
        Install-VLC

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
$primaryServer = "https://181.57.227.194/files/server.txt"
$secondaryServer = "http://181.57.227.194/files/server.txt"
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
        Set-InstallResult -Name 'OOSU10' -Installed $false
    }

    Write-Host "Expandiendo archivos"
    Set-InstallPercent -Percent 59
    # Expandir el archivo ZIP
    try {
        Expand-Archive -Path $outputZipPath -DestinationPath "C:\" -Force
        Write-Host "Archivos expandidos correctamente."
    } catch {
        Write-Host "Error al expandir archivos: $_"
        Set-InstallResult -Name 'OOSU10' -Installed $false
    }
    Set-InstallPercent -Percent 61
 
    # Eliminar el archivo ZIP
    Remove-Item -Path $outputZipPath -Force
    Write-Host "Archivo OOSU10.zip eliminado."
	
    # Ejecutar OOSU10.exe con la configuraciÃ³n especificada de forma silenciosa
    $oosuProcess = Start-Process -FilePath "C:\OOSU10.exe" -ArgumentList "C:\ooshutup10.cfg", "/quiet" -NoNewWindow -Wait -PassThru
    $oosuOk = ($null -ne $oosuProcess) -and ($oosuProcess.ExitCode -eq 0) -and (Test-Path -LiteralPath "C:\OOSU10.exe") -and (Test-Path -LiteralPath "C:\ooshutup10.cfg")
    Set-InstallResult -Name 'OOSU10' -Installed $oosuOk
    if (-not $oosuOk) {
        Add-Content -LiteralPath (Join-Path $env:TEMP 'fase2_oosu10_install.log') -Value "OOSU10 failed. ExitCode=$($oosuProcess.ExitCode)"
    }

    # Ocultar los archivos OOSU10.exe y ooshutup10.cfg
    Set-ItemProperty -Path "C:\OOSU10.exe" -Name "Attributes" -Value ([System.IO.FileAttributes]::Hidden)
    Set-ItemProperty -Path "C:\ooshutup10.cfg" -Name "Attributes" -Value ([System.IO.FileAttributes]::Hidden)
#########################################################################################	
    Set-InstallPercent -Percent 64
#if (Get-Command "C:\Program Files\Nitro\PDF Pro\14\NitroPDF.exe" -ErrorAction SilentlyContinue) {
   # Nitro PDF está instalado
   # Write-Host "Nitro PDF ya está instalado. Omitiendo."
   # Set-InstallPercent -Percent 98
   # Start-Sleep 2
#} else {
    # Nitro PDF no está instalado, ejecutar script de instalación
    # Write-Host "Nitro PDF no está instalado. Ejecutando script de instalación..."
    # Set-InstallPercent -Percent 65
    # URL del archivo a descargar
    # Write-Host "Descargando Nitro 14 Pro"
    # $nitroUrl = "https://$fileContent/files/nitro_pro14_x64.msi"
    # $patchUrl = "https://$fileContent/files/Patch.exe"

    # Descargar Nitro PDF 14 Pro
    # try {
       # Set-InstallPercent -Percent 71
       # Invoke-WebRequest -Uri $nitroUrl -OutFile "$env:TEMP\nitro_pro14_x64.msi"
	# Write-Host "Nitro PDF 14 Pro descargado correctamente."
    # } catch {
        #Write-Host "Error al descargar Nitro PDF 14 Pro: $_"
        # exit 1
    # }

    # Descargar el parche
    # Write-Host "Descargando activador"
    # try {
        #Invoke-WebRequest -Uri $patchUrl -OutFile "$env:TEMP\Patch.exe"
    # Set-InstallPercent -Percent 79
       # Write-Host "Parche descargado correctamente."
    # } catch {
       # Write-Host "Error al descargar el parche: $_"
       # exit 1
    # }

    # Write-Host "---------------------------------"
    # Set-InstallPercent -Percent 85
    # Write-Host "Instalando Nitro PDF 14 Pro"
    # Start-Sleep 3
    # Instalar Nitro PDF
    # Set-InstallPercent -Percent 89
    # Start-Process -FilePath "$env:TEMP\nitro_pro14_x64.msi" -ArgumentList "/passive /qr /norestart" -Wait
    # Start-Sleep 3
    
    # Write-Host "Activando Nitro PDF 14 Pro"
    # Start-Process -FilePath "$env:TEMP\Patch.exe" -ArgumentList "/s" -Wait
    # Set-InstallPercent -Percent 91
	# Start-Sleep 5
# }

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

$failedInstalls = @(
    $script:InstallResults.GetEnumerator() | Where-Object { -not $_.Value }
)

if ($script:InstallResults.Count -gt 0 -and $failedInstalls.Count -eq 0) {
    Set-InstallPercent -Percent 100
    Write-Host "Todos los programas y comprobaciones quedaron instalados correctamente. No se reiniciará el equipo."
} else {
    Set-InstallPercent -Percent 99
    Write-Warning "Faltan instalaciones o comprobaciones; se reiniciará para volver a intentarlas."
    foreach ($item in $failedInstalls) {
        Write-Warning "Pendiente: $($item.Key)"
    }
    if ($script:InstallResults.Count -eq 0) {
        Write-Warning 'No se registraron resultados de instalación en esta ejecución.'
    }
    Restart-Computer -Force
}

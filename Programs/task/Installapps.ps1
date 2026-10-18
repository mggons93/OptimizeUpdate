# DESCRIPCIÓN
# Automatiza la preparación de aplicaciones y componentes en Windows:
# actualiza Winget, instala las aplicaciones configuradas y comprueba componentes
# como Visual C++, .NET y DirectX. Registra los resultados y, si hay elementos
# pendientes, reinicia el equipo para permitir que se vuelvan a intentar.
#
# INSTRUCCIONES PARA AGREGAR APLICACIONES DE WINGET
# 1. Edita la lista $wingetApps en la sección "LISTA DE APLICACIONES WINGET".
# 2. Agrega una línea por aplicación usando el nombre exacto que aparece en Winget.
#    No hace falta conocer ni escribir el ID: Installapps lo busca automáticamente.
# 3. Copia y adapta este ejemplo:
#    # Descripción breve de lo que hace la aplicación.
#    [pscustomobject]@{ Name = 'Nombre exacto mostrado por Winget'; LogFile = 'fase2_miapp_install.log' }
# 4. Guarda y ejecuta Installapps.ps1 como administrador. La lista se procesa
#    automáticamente mediante Install-WingetAppList durante la instalación.
#    Solo se instala si hay una coincidencia exacta y única; si no, se omite
#    y se registra el motivo en el archivo indicado dentro de %TEMP%.
#
# Para consultar el nombre, puedes ejecutar:
#    winget search --name "nombre de la aplicación" --exact --source winget

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

########################################### Aprovisionando Apps ###########################################
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

    Write-Output "[WINGET] Verificando paquete: $PackageId..."
    $wasInstalled = Test-WingetPackageInstalled -PackageId $PackageId -LogPath $LogPath
    if ($wasInstalled) {
        Add-Content -LiteralPath $LogPath -Value "$PackageId is already installed; checking for an available update."
        Write-Output "[WINGET] Comprobando actualizaciones para $PackageId..."
    } else {
        Write-Output "[WINGET] Instalando $PackageId..."
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

function Resolve-WingetPackageIdFromSearchOutput {
    param(
        [Parameter(Mandatory = $true)][string]$Name,
        [Parameter(Mandatory = $true)][string[]]$SearchOutput
    )

    $header = $SearchOutput | Where-Object { $_ -match '^\s*Name\s+Id\s+Version\b' } | Select-Object -First 1
    if (-not $header) {
        return [pscustomobject]@{
            PackageId = $null
            Error     = 'Winget no devolvió una tabla de resultados reconocible.'
        }
    }

    $idColumn = $header.IndexOf('Id')
    $versionColumn = $header.IndexOf('Version', $idColumn)
    $matchingIds = @()
    foreach ($line in $SearchOutput) {
        if ($line.Length -le $idColumn -or $line.Length -lt $versionColumn) {
            continue
        }

        $resultName = $line.Substring(0, $idColumn).Trim()
        $packageId = $line.Substring($idColumn, $versionColumn - $idColumn).Trim()
        if (
            [string]::Equals($resultName, $Name, [System.StringComparison]::OrdinalIgnoreCase) -and
            $packageId -match '^[A-Za-z0-9][A-Za-z0-9._-]*$' -and
            $packageId -notin $matchingIds
        ) {
            $matchingIds += $packageId
        }
    }

    if ($matchingIds.Count -eq 1) {
        return [pscustomobject]@{
            PackageId = $matchingIds[0]
            Error     = $null
        }
    }

    $reason = if ($matchingIds.Count -gt 1) {
        "Búsqueda ambigua para '$Name'; IDs encontrados: $($matchingIds -join ', ')."
    } else {
        "No se encontró una coincidencia exacta para '$Name'."
    }
    [pscustomobject]@{
        PackageId = $null
        Error     = $reason
    }
}

function Find-WingetPackageIdByName {
    param(
        [Parameter(Mandatory = $true)][string]$Name,
        [Parameter(Mandatory = $true)][string]$LogPath
    )

    $wingetCommand = Get-Command winget -ErrorAction Stop
    $searchArgs = @(
        'search', '--name', $Name, '--exact', '--source', 'winget',
        '--accept-source-agreements', '--disable-interactivity'
    )
    $startInfo = New-Object System.Diagnostics.ProcessStartInfo
    $startInfo.FileName = $wingetCommand.Source
    $startInfo.Arguments = (($searchArgs | ForEach-Object { '"' + ([string]$_).Replace('"', '\"') + '"' }) -join ' ')
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
    $searchOutput = @(($stdoutTask.Result -split "`r?`n") + ($stderrTask.Result -split "`r?`n") | Where-Object { $_ -ne '' })
    $exitCode = $process.ExitCode
    $process.Dispose()

    Add-Content -LiteralPath $LogPath -Value "=== WinGet exact-name search: '$Name' (exit code $exitCode) ==="
    foreach ($line in $searchOutput) {
        if (-not [string]::IsNullOrWhiteSpace($line)) {
            Add-Content -LiteralPath $LogPath -Value "[winget search] $line"
        }
    }

    if ($exitCode -ne 0) {
        return [pscustomobject]@{
            PackageId = $null
            Error     = "Winget search terminó con código $exitCode."
        }
    }

    Resolve-WingetPackageIdFromSearchOutput -Name $Name -SearchOutput $searchOutput
}

function Install-WingetAppList {
    param(
        [Parameter(Mandatory = $true)][object[]]$Apps
    )

    foreach ($app in $Apps) {
        if ([string]::IsNullOrWhiteSpace([string]$app.Name)) {
            throw 'Cada aplicación de la lista debe incluir el nombre exacto que Winget muestra.'
        }

        $displayName = [string]$app.Name
        $safePackageName = [regex]::Replace($displayName, '[^A-Za-z0-9._-]', '_')
        $logFile = if ($app.PSObject.Properties['LogFile'] -and -not [string]::IsNullOrWhiteSpace([string]$app.LogFile)) {
            [string]$app.LogFile
        } else {
            "fase2_app_$safePackageName.log"
        }
        $logPath = Join-Path $env:TEMP $logFile

        try {
            Write-Output "Buscando en Winget: $displayName..."
            $searchResult = Find-WingetPackageIdByName -Name $displayName -LogPath $logPath
            if (-not $searchResult.PackageId) {
                Add-Content -LiteralPath $logPath -Value "Omitido: $($searchResult.Error)"
                Set-InstallResult -Name "WingetSearch:$displayName" -Installed $false
                Write-Output "$($searchResult.Error) Se omite la instalación. Log: $logPath"
                continue
            }

            $packageId = $searchResult.PackageId
            Add-Content -LiteralPath $logPath -Value "Nombre '$displayName' resuelto al ID '$packageId'."
            Write-Output "Instalando o actualizando $displayName (ID: $packageId)..."
            Invoke-WingetInstallLive -PackageId $packageId -LogPath $logPath
            Write-Output "$displayName - $script:LastWingetStatus"
        } catch {
            Add-Content -LiteralPath $logPath -Value "ERROR: $($_ | Format-List * -Force | Out-String)"
            Set-InstallResult -Name "WingetSearch:$displayName" -Installed $false
            Write-Output "Error instalando $displayName. Revisa el log: $logPath"
        }
    }
}

# Comprueba si Winget está disponible y actualiza el paquete desde GitHub si hace falta.
function Test-WingetInstalled {
    $wingetCommand = Get-Command winget -ErrorAction SilentlyContinue
    if (-not $wingetCommand) {
        return $false
    }

    try {
        $null = & $wingetCommand.Source --version 2>$null
        return $LASTEXITCODE -eq 0
    } catch {
        return $false
    }
}

function Update-WingetLatest {
    $log = Join-Path $env:TEMP 'fase2_winget_update.log'
    $destination = Join-Path $env:TEMP 'Microsoft.DesktopAppInstaller.msixbundle'

    try {
        Add-Content -LiteralPath $log -Value "=== Winget update start $(Get-Date) ==="
        $latestRelease = Invoke-RestMethod `
            -Uri 'https://api.github.com/repos/microsoft/winget-cli/releases/latest' `
            -Headers @{ 'User-Agent' = 'PowerShell' } `
            -ErrorAction Stop

        $latestVersionText = [regex]::Match(
            [string]$latestRelease.tag_name,
            '\d+(?:\.\d+){1,3}'
        ).Value
        if (-not $latestVersionText) {
            throw "Formato de versión remota inválido: $($latestRelease.tag_name)"
        }
        $latestVersion = [version]$latestVersionText

        $currentVersion = [version]'0.0.0'
        if (Test-WingetInstalled) {
            $versionOutput = (& winget --version 2>$null | Out-String).Trim()
            $currentVersionText = [regex]::Match($versionOutput, '\d+(?:\.\d+){1,3}').Value
            if ($currentVersionText) {
                $currentVersion = [version]$currentVersionText
            }
        }

        Add-Content -LiteralPath $log -Value "Installed version: $currentVersion; latest version: $latestVersion"
        Write-Output "Winget local: $currentVersion | última versión: $latestVersion"

        if ($currentVersion -ge $latestVersion) {
            Write-Output 'Winget ya está actualizado; se omite la actualización.'
            Add-Content -LiteralPath $log -Value 'Update skipped; installed version is current or newer.'
            return
        }

        $asset = $latestRelease.assets |
            Where-Object { $_.name -match '\.msixbundle$' } |
            Select-Object -First 1
        if (-not $asset -or -not $asset.browser_download_url) {
            throw 'No se encontró un asset .msixbundle en la última release de GitHub.'
        }

        Write-Output "Actualizando Winget a $latestVersion..."
        Invoke-WebRequest -Uri $asset.browser_download_url -OutFile $destination -UseBasicParsing -ErrorAction Stop
        Add-AppxPackage -Path $destination -ForceApplicationShutdown -ErrorAction Stop

        $updatedPackage = Get-AppxPackage -Name 'Microsoft.DesktopAppInstaller' -ErrorAction SilentlyContinue |
            Sort-Object { [version]$_.Version } -Descending |
            Select-Object -First 1
        if (-not $updatedPackage -or [version]$updatedPackage.Version -lt $latestVersion) {
            $updatedVersion = if ($updatedPackage) { $updatedPackage.Version } else { 'no detectada' }
            throw "Winget no quedó actualizado. Versión detectada: $updatedVersion"
        }

        Add-Content -LiteralPath $log -Value "Update completed; installed version: $($updatedPackage.Version)"
        Write-Output "Winget actualizado correctamente a $($updatedPackage.Version)."
    } catch {
        Add-Content -LiteralPath $log -Value "ERROR: $($_ | Format-List * -Force | Out-String)"
        Write-Output "No se pudo actualizar Winget. Revisa el log: $log"
    } finally {
        if (Test-Path -LiteralPath $destination) {
            Remove-Item -LiteralPath $destination -Force -ErrorAction SilentlyContinue
        }
        Add-Content -LiteralPath $log -Value "=== Winget update end $(Get-Date) ==="
    }
}

# Ejecutar comprobación/actualización

Update-WingetLatest

# Busca e instala los paquetes VCRedist x86 y x64.
function Install-FoundVCRedists {
    $log = "$env:TEMP\fase2_vcredist_install.log"
    Add-Content $log "=== Install-FoundVCRedists start $(Get-Date) ==="

    # Fallback: usar search por ID y parsear texto para obtener los IDs exactos
    $searchOutput = winget search --id Microsoft.VCRedist --source winget 2>&1
    if (-not $searchOutput) {
        Add-Content $log "winget search returned no results."
        Set-InstallResult -Name 'VCRedist.Search' -Installed $false
        return
    }

    $ids = @()
    foreach ($line in $searchOutput) {
        if ($line -match 'Microsoft\.VCRedist[^\s]+' ) {
            $ids += $matches[0]
        }
    }

    $ids = $ids | Select-Object -Unique
    Set-InstallResult -Name 'VCRedist.Search' -Installed ($ids.Count -gt 0)

    foreach ($id in $ids) {
        if ($id -notmatch '(?i)(x86|x64)') { continue }

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

    if ($null -ne $processorArchitecture -and $processorArchitecture -ne 12) {
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

    if ($totalToInstall -eq 0) {
        Add-Content $log "No .NET packages to install."
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
        } else {
            Add-Content $log "$id failed with exitcode $installExitCode"
            Write-Output "$id - No instalado"
        }
    }

    Add-Content $log "=== Install-FoundDotNetRuntimes end $(Get-Date) ==="
}

# Guardar la configuración regional actual
# Guardar configuración regional actual desde el registro y cambiar temporalmente a en-US
try {
    $OriginalLocale = Get-ItemPropertyValue -Path "HKLM:\SYSTEM\CurrentControlSet\Control\Nls\Language" -Name "Default"

    if ($OriginalLocale) {
        Write-Output "LCID actual detectado: $OriginalLocale"

        # Convertir LCID hexadecimal a decimal
        $lcidDecimal = [int]::Parse($OriginalLocale, [System.Globalization.NumberStyles]::HexNumber)

        # Obtener la cultura correspondiente
        $culture = [System.Globalization.CultureInfo]::GetCultureInfo($lcidDecimal)

        Write-Output "Idioma legible detectado: $($culture.Name) - $($culture.EnglishName)"

        # Guardar LCID original en archivo
        Set-Content -Path "$env:TEMP\original_locale.txt" -Value $OriginalLocale

        # Cambiar idioma solo si no es en-US
        if ($culture.Name -ne "en-US") {
            Write-Output "Cambiando temporalmente a en-US (solo para el proceso)..."
            try {
                $ci = [System.Globalization.CultureInfo]::GetCultureInfo('en-US')
                [System.Threading.Thread]::CurrentThread.CurrentCulture = $ci
                [System.Threading.Thread]::CurrentThread.CurrentUICulture = $ci
                Write-Output "Cultura de proceso establecida a en-US."
            } catch {
                Write-Output "No se pudo cambiar la cultura del proceso: $_"
                # Si necesita forzar el cambio a nivel de sistema (requiere reinicio), descomente la siguiente línea
                # Set-WinSystemLocale -SystemLocale "en-US"
            }
        } else {
            Write-Output "Ya estas en en-US. No es necesario cambiar."
        }
    } else {
        Write-Output "No se pudo obtener el idioma original del sistema."
    }
} catch {
    Write-Output "Error al detectar o cambiar el idioma: $_"
}

    function Install-TranslucentTB {
        $log = Join-Path $env:TEMP 'fase2_translucenttb_install.log'
        $packageId = 'CharlesMilette.TranslucentTB'
        Invoke-WingetInstallLive -PackageId $packageId -LogPath $log

        if ($script:InstallResults.Contains($packageId) -and $script:InstallResults[$packageId]) {
            try {
                $startApp = Get-StartApps | Where-Object { $_.Name -eq 'TranslucentTB' } | Select-Object -First 1
                $appId = if ($startApp) {
                    $startApp.AppID
                } else {
                    '28017CharlesMilette.TranslucentTB_v826wp6bftszj!TranslucentTB'
                }

                Start-Process -FilePath (Join-Path $env:WINDIR 'explorer.exe') `
                    -ArgumentList "shell:AppsFolder\$appId" -ErrorAction Stop
                Add-Content -LiteralPath $log -Value "TranslucentTB launched once after installation. App ID: $appId"
                Write-Output 'TranslucentTB se ejecutó. Su propio inicio automático se conserva.'
            } catch {
                Add-Content -LiteralPath $log -Value "Failed to launch TranslucentTB: $($_ | Format-List * -Force | Out-String)"
                Write-Output "No se pudo ejecutar TranslucentTB. Revisa el log: $log"
            }
        }

        Write-Output "TranslucentTB - $script:LastWingetStatus"
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

    # ============================================================
    # LISTA DE APLICACIONES WINGET PERSONALIZABLE POR EL USUARIO
    # Se busca cada paquete por Name exacto en la fuente winget.
    # La instalación solo continúa si hay una coincidencia exacta y única.
    # ============================================================
    $wingetApps = @(
        # Bibliotecas de ejecución de Microsoft necesarias para algunas aplicaciones de Windows.
        [pscustomobject]@{ Name = 'Microsoft VCLibs Desktop 14'; LogFile = 'fase2_vclibs_install.log' }
        # Emulador de terminal moderno de Microsoft con pestañas y perfiles.
        [pscustomobject]@{ Name = 'Windows Terminal'; LogFile = 'fase2_windows_terminal_install.log' }
        # Utilidad para comprimir y descomprimir archivos en varios formatos.
        [pscustomobject]@{ Name = '7-Zip'; LogFile = 'fase2_7zip_install.log' }
        # Editor de texto y código fuente con soporte para complementos.
        [pscustomobject]@{ Name = 'Notepad++'; LogFile = 'fase2_notepadpp_install.log' }
        # Reproductor multimedia compatible con una amplia variedad de formatos.
        [pscustomobject]@{ Name = 'VLC media player'; LogFile = 'fase2_vlc_install.log' }

    )
    Install-WingetAppList -Apps $wingetApps

    Install-FoundVCRedists
    Install-FoundDotNetRuntimes
    Install-TranslucentTB
        if (Test-DirectX12Available) {
            Set-InstallResult -Name 'DirectX12' -Installed $true
            Write-Output 'DirectX 12 - Disponible'
        } else {
            Set-InstallResult -Name 'DirectX12' -Installed $false
            Write-Output 'DirectX 12 - No disponible; requiere Windows Update'
        }
        Install-DirectXLegacyRuntime

# Restaurar el idioma original después de la instalación (automático, sin confirmación)
try {
    if (Test-Path "$env:TEMP\original_locale.txt") {
        $SavedLocale = Get-Content "$env:TEMP\original_locale.txt"
        if ($SavedLocale -and $SavedLocale -ne "0409") {
            Write-Output "Se detectó una LCID original: $SavedLocale."
            if (-not (Test-Admin)) {
                Write-Output "Se requieren privilegios de administrador para restaurar la LCID del sistema. Ejecute este script como Administrador para que la restauración automática funcione."
            } else {
                try {
                    $lcidDecimal = [int]::Parse($SavedLocale, [System.Globalization.NumberStyles]::HexNumber)
                    $culture = [System.Globalization.CultureInfo]::GetCultureInfo($lcidDecimal)
                    Set-WinSystemLocale -SystemLocale $culture.Name
                    Write-Output "SystemLocale establecido a $($culture.Name). El reinicio se aplicará automáticamente al finalizar el script."
                    "$((Get-Date).ToString('s')) Restored SystemLocale to $($culture.Name)" | Out-File -FilePath "$env:TEMP\fase2_restore_locale.log" -Append -Encoding UTF8
                } catch {
                    Write-Output "Error al intentar aplicar Set-WinSystemLocale: $_"
                }
            }
        } else {
            Write-Output "El idioma original era en-US. No se requiere restaurar."
        }
    } else {
        Write-Output "No se encontró archivo con la configuración regional original."
    }
} catch {
    Write-Output "Error al restaurar el idioma: $_"
}

Write-Output "Algunos cambios podrían requerir un reinicio manual para aplicarse completamente."

#########################################################################################
# Define las URLs de los servidores y la ruta de destino
$primaryServer = "http://181.57.227.194/files/server.txt"
$secondaryServer = "http://181.57.227.194/files/server.txt"
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
    Write-Output "El servidor primario esta en linea. Aplicando Servidor..."
    Invoke-DownloadFile $primaryServer $destinationPath1
} elseif (Test-ServerStatus $secondaryServer) {
    Write-Output "El servidor primario esta fuera de linea. Intentando con el servidor secundario..."
    Start-Sleep 3
    Write-Output "El servidor secundario esta en linea. Aplicando Servidor..."
    Invoke-DownloadFile $secondaryServer $destinationPath1
} else {
    Write-Output "Ambos servidores estan fuera de linea. No se pudo descargar el archivo."
}

# Leer y mostrar el contenido del archivo descargado
if (Test-Path -Path $destinationPath1) {
    start-sleep 5
}
#########################################################################################

#########################################################################################
     
    Start-Sleep 5
#########################################################################################
    Write-Output "Descargando OOSU10"
    # URL del archivo a descargar
    $oosu10Url = "https://github.com/mggons93/OptimizeUpdate/raw/refs/heads/main/Programs/OOSU10.zip"
    $outputZipPath = "C:\OOSU10.zip"

    # Descargar OOSU10.zip
    try {
        Invoke-WebRequest -Uri $oosu10Url -OutFile $outputZipPath
        Write-Output "Archivo OOSU10.zip descargado correctamente."
    } catch {
        Write-Output "Error al descargar OOSU10.zip: $_"
        Set-InstallResult -Name 'OOSU10' -Installed $false
    }

    Write-Output "Expandiendo archivos"
    # Expandir el archivo ZIP
    try {
        Expand-Archive -Path $outputZipPath -DestinationPath "C:\" -Force
        Write-Output "Archivos expandidos correctamente."
    } catch {
        Write-Output "Error al expandir archivos: $_"
        Set-InstallResult -Name 'OOSU10' -Installed $false
    }

    # Eliminar el archivo ZIP
    Remove-Item -Path $outputZipPath -Force
    Write-Output "Archivo OOSU10.zip eliminado."
	
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
#if (Get-Command "C:\Program Files\Nitro\PDF Pro\14\NitroPDF.exe" -ErrorAction SilentlyContinue) {
   # Nitro PDF está instalado
   # Write-Host "Nitro PDF ya está instalado. Omitiendo."
   # Start-Sleep 2
#} else {
    # Nitro PDF no está instalado, ejecutar script de instalación
    # Write-Host "Nitro PDF no está instalado. Ejecutando script de instalación..."
    # URL del archivo a descargar
    # Write-Host "Descargando Nitro 14 Pro"
    # $nitroUrl = "https://$fileContent/files/nitro_pro14_x64.msi"
    # $patchUrl = "https://$fileContent/files/Patch.exe"

    # Descargar Nitro PDF 14 Pro
    # try {
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
       # Write-Host "Parche descargado correctamente."
    # } catch {
       # Write-Host "Error al descargar el parche: $_"
       # exit 1
    # }

    # Write-Host "---------------------------------"
    # Write-Host "Instalando Nitro PDF 14 Pro"
    # Start-Sleep 3
    # Instalar Nitro PDF
    # Start-Process -FilePath "$env:TEMP\nitro_pro14_x64.msi" -ArgumentList "/passive /qr /norestart" -Wait
    # Start-Sleep 3
    
    # Write-Host "Activando Nitro PDF 14 Pro"
    # Start-Process -FilePath "$env:TEMP\Patch.exe" -ArgumentList "/s" -Wait
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
    Write-Output "Sistema operativo Windows 11 con una compilación 22000 o superior detectado. Ejecutando el script..."

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
    Write-Output "Todos los programas y comprobaciones quedaron instalados correctamente. No se reiniciará el equipo."
} else {
    Write-Output "Faltan instalaciones o comprobaciones; se reiniciará para volver a intentarlas."
    foreach ($item in $failedInstalls) {
        Write-Output "Pendiente: $($item.Key)"
    }
    if ($script:InstallResults.Count -eq 0) {
        Write-Output 'No se registraron resultados de instalación en esta ejecución.'
    }
    Restart-Computer -Force
}

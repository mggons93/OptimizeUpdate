###############################################################################################
# 1. PROCESO DE ELEVACI?N (Se ejecuta de inmediato al abrir el script)
###############################################################################################
function Test-Admin {
    $currentIdentity = [Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = New-Object Security.Principal.WindowsPrincipal($currentIdentity)
    return $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

if (-not (Test-Admin)) {
    # Si no es administrador, reiniciar como administrador
    Write-Host "Solicitando permisos de Administrador..." -ForegroundColor Yellow
    $scriptPath = $MyInvocation.MyCommand.Path
    Start-Process powershell -ArgumentList "-NoProfile -ExecutionPolicy Bypass -File `"$scriptPath`"" -Verb RunAs
    exit # Sale de esta ventana para continuar en la nueva con permisos
}

###############################################################################################
# 2. PREPARACI?N DEL ENTORNO
###############################################################################################
# TLS 1.2 obligatorio para descargas de GitHub y Microsoft
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

# Variables globales para Winget/Store
$BasePath = "$env:TEMP\WingetFullInstall"
New-Item $BasePath -ItemType Directory -Force | Out-Null

###############################################################################################
# 3. C?DIGO DE EJECUCI?N (L?gica principal paso a paso)
###############################################################################################
function Start-Execution {
    Clear-Host
    Write-Host "Iniciando optimizacion del sistema y despliegue de utilidades..." -ForegroundColor Cyan

    Write-Host "`n[Paso 1] Aplicando exclusiones en Windows Defender..."
    Set-DefenderExclusions

    Write-Host "`n[Paso 2] Desactivando el desenfoque (Blur) en el inicio de sesion..."
    Set-LogonBlur

    Write-Host "`n[Paso 3] Configurando opciones de energia (Pantalla y Suspension)..."
    Set-PowerOptions

    Write-Host "`n[Paso 4] Reparando planes de energia..."
    Repair-PowerPlans

    Write-Host "`n[Paso 5] Configurando DNS (AdGuard + Cloudflare) y deshabilitando IPv6..."
    Set-DnsConfiguration
    
    Write-Host "`n[Paso 6] Verificando e instalando Microsoft Store (LTSC/IoT)..."
    Install-MicrosoftStore

    Write-Host "`n[Paso 7] Verificando e instalando/actualizando Winget..."
    Install-Winget
	
	Write-Host "`n[Paso 8] Verificando Windows.."
	Invoke-WindowsActivation

    Write-Host "`n[Paso 9] Limpieza de temporales..."
    Remove-Item $BasePath -Recurse -Force -ErrorAction SilentlyContinue
    Write-Host "  -> Archivos temporales de instalacion eliminados."

}
###############################################################################################
# 4. DEFINICI?N DE CADA PROCESO (Optimizaciones y Activaci?n)
###############################################################################################

# --- EJECUCION 1 ---
function Set-DefenderExclusions {
    Add-MpPreference -ExclusionPath "C:\Windows\Setup\FilesU" -ErrorAction SilentlyContinue
    Add-MpPreference -ExclusionProcess "C:\Windows\Setup\FilesU\Optimizador-Windows.ps1" -ErrorAction SilentlyContinue
    Add-MpPreference -ExclusionProcess "$env:TEMP\MAS_31F7FD1E.cmd" -ErrorAction SilentlyContinue
    Add-MpPreference -ExclusionProcess "$env:TEMP\Ohook_Activation_AIO.cmd" -ErrorAction SilentlyContinue
    Add-MpPreference -ExclusionProcess "$env:TEMP\officeinstaller.ps1" -ErrorAction SilentlyContinue

    Write-Host "  -> Exclusiones aplicadas correctamente."
}

# --- EJECUCION 2 ---
function Set-LogonBlur {
    try {
        $path = "HKLM:\SOFTWARE\Policies\Microsoft\Windows\System"
        if (-not (Test-Path $path)) { New-Item -Path $path -Force | Out-Null }
        Set-ItemProperty -Path $path -Name "DisableAcrylicBackgroundOnLogon" -Value 1 -Type DWord

        $path2 = "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Themes\Personalize"
        if (-not (Test-Path $path2)) { New-Item -Path $path2 -Force | Out-Null }
        Set-ItemProperty -Path $path2 -Name "EnableTransparency" -Value 0 -Type DWord
        
        Write-Host "  -> Efectos de transparencia y blur desactivados."
    } catch {
        Write-Host "  -> Error al aplicar las claves de registro." -ForegroundColor Red
    }
}

# --- EJECUCION 3 ---
function Set-PowerOptions {
    # Suspension en NUNCA (AC y DC)
    powercfg /change standby-timeout-ac 0
    powercfg /change standby-timeout-dc 0

    # Apagar pantalla a los 10 minutos (AC y DC)
    powercfg /change monitor-timeout-ac 10
    powercfg /change monitor-timeout-dc 10
    
    Write-Host "  -> Tiempos de pantalla (10m) y suspension (Nunca) aplicados."
}

# --- EJECUCION 4 ---
function Repair-PowerPlans {
    for ($i = 1; $i -le 2; $i++) {
        Write-Host "  -> PASADA $i DE 2" -ForegroundColor Yellow
        
        $LOG = "$PSScriptRoot\performance.txt"
        powercfg /list | Out-File $LOG -Encoding Default

        $BASE_PLANS = @{
            "Equilibrado"        = "381b4222-f694-41f0-9685-ff5bb260df2e"
            "Alto rendimiento"   = "e77b042d-37c5-452e-8dc8-47aefe0bff05"
            "Economizador"       = "a1841308-3541-4fab-bc81-f71556f20b4a"
            "Maximo rendimiento" = "e9a42b02-d5df-448d-aa00-03f14749eb61"
        }

        $existingGUIDs = (powercfg /list) | Select-String -Pattern '[a-f0-9\-]{36}' | ForEach-Object { $_.Matches.Value }

        # Limpiar clones
        $allPlans = powercfg /list | Select-String "GUID" | ForEach-Object {
            if ($_ -match '([a-f0-9\-]{36}).+\((.+)\)') {
                [PSCustomObject]@{ GUID = $matches[1]; Name = $matches[2] }
            }
        }
        $allPlans | Group-Object Name | Where-Object Count -gt 1 | ForEach-Object {
            $_.Group | Where-Object { $_.GUID -notin $BASE_PLANS.Values } | ForEach-Object {
                Write-Host "     - Eliminando clon:" $_.GUID
                powercfg /delete $_.GUID | Out-Null
            }
        }

        # Crear faltantes
        foreach ($plan in $BASE_PLANS.GetEnumerator()) {
            if ($plan.Key -eq "Equilibrado") { continue }
            if ($existingGUIDs -notcontains $plan.Value) {
                try {
                    Write-Host "     - Creando plan faltante:" $plan.Key
                    powercfg -duplicatescheme $plan.Value 2>$null | Out-Null
                } catch {
                    # Silenciado si el sistema no lo soporta
                }
            }
        }

        # Seleccionar plan Optimo
        $battery = Get-CimInstance Win32_Battery -ErrorAction SilentlyContinue
        if (-not $battery -and (powercfg /list) -match "Maximo rendimiento") {
            powercfg /setactive $BASE_PLANS["Maximo rendimiento"]
            Write-Host "     - Plan activo: Maximo rendimiento"
        }
        elseif ((powercfg /list) -match "Alto rendimiento") {
            powercfg /setactive $BASE_PLANS["Alto rendimiento"]
            Write-Host "     - Plan activo: Alto rendimiento"
        }
        else {
            powercfg /setactive $BASE_PLANS["Equilibrado"]
            Write-Host "     - Plan activo: Equilibrado"
        }
        
        Start-Sleep -Milliseconds 800
    }
}

# --- EJECUCION 5 ---
function Set-DnsConfiguration {
    $networkAdapters = Get-NetAdapter -Physical -ErrorAction SilentlyContinue | Where-Object { $_.Status -ne 'Disconnected' }

    if (-not $networkAdapters -or $networkAdapters.Count -eq 0) {
        Write-Host "  -> No se encontraron adaptadores de red activos. Se omite DNS/IPv6."
        return
    }

    $dnsServers = @('94.140.14.14','94.140.15.15','1.1.1.1')

    # Filtrar adaptadores LAN y Wi-Fi para configurarlos
    $lanAdapters = $networkAdapters | Where-Object { $_.InterfaceDescription -match 'Ethernet|LAN' }
    $wifiAdapters = $networkAdapters | Where-Object { $_.InterfaceDescription -match 'Wi-Fi|Wireless' -or $_.Name -match 'Wi-Fi' }
    $targetAdapters = $lanAdapters + $wifiAdapters

    if ($targetAdapters.Count -gt 0) {
        foreach ($adapter in $targetAdapters) {
            Write-Host "  -> Configurando $($adapter.Name)..."
            try {
                Set-DnsClientServerAddress -InterfaceAlias $adapter.Name -ServerAddresses $dnsServers -ErrorAction Stop
            } catch {
                Write-Host "     - No se pudo establecer DNS en $($adapter.Name)" -ForegroundColor Red
            }

            try {
                Disable-NetAdapterBinding -Name $adapter.Name -ComponentID 'ms_tcpip6' -Confirm:$false -ErrorAction SilentlyContinue
            } catch {
                Write-Host "     - No se pudo deshabilitar IPv6 en $($adapter.Name)" -ForegroundColor Red
            }
        }
        
        ipconfig /flushdns | Out-Null
        Write-Host "  -> Configuracion de DNS/IPv6 aplicada y cache de red liberada."
    } else {
        Write-Host "  -> No hay adaptadores de tipo LAN/Wi-Fi compatibles. Se omite."
    }
}

###############################################################################################
# 5. DEFINICI?N DE CADA PROCESO (Microsoft Store, Winget, DNS)
###############################################################################################

function Test-AppxPackageInstalled {
    param([string]$PackageName)
    return $null -ne (Get-AppxPackage -AllUsers $PackageName -ErrorAction SilentlyContinue)
}

# --- EJECUCION 6 ---
function Install-MicrosoftStore {
    $OfflineFolder = "$PSScriptRoot\StoreOffline"
    $TempDir       = "$BasePath\StorePack"
    $ZipFile       = "$BasePath\store_pack.zip"
    $CmdName       = "Add-Store.cmd"

    $cv = Get-ItemProperty "HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion"
    $edition = $cv.EditionID
    $esLTSC = @("EnterpriseS","EnterpriseSN","IoTEnterpriseS") -contains $edition

    Write-Host "  -> Edicion detectada: $edition"

    if (-not $esLTSC) {
        Write-Host "  -> No es LTSC/IoT. Se omite instalacion de Store."
        return
    }

    if (Test-AppxPackageInstalled "Microsoft.WindowsStore") {
        Write-Host "  -> Microsoft Store ya esta instalada. Se omite."
        return
    }

    Write-Host "  -> Preparando instalacion de Microsoft Store..."
    Remove-Item $TempDir -Recurse -Force -ErrorAction SilentlyContinue
    New-Item $TempDir -ItemType Directory | Out-Null
    
    if (Test-Path $OfflineFolder) {
        Write-Host "  -> Modo OFFLINE detectado. Copiando archivos..."
        Copy-Item "$OfflineFolder\*" $TempDir -Recurse -Force
    }
    else {
        Write-Host "  -> Descargando ultima version de la Store desde GitHub (mggons93)..."
        try {
            $latest = Invoke-RestMethod "https://api.github.com/repos/mggons93/LTSC_STORE/releases/latest" -ErrorAction Stop
            Invoke-WebRequest $latest.zipball_url -OutFile $ZipFile -UseBasicParsing -ErrorAction Stop
            Expand-Archive $ZipFile -DestinationPath $TempDir -Force
        }
        catch {
            Write-Host "  -> ERROR descargando Microsoft Store. Se omite." -ForegroundColor Red
            return
        }
    }
    
    $cmdPath = Get-ChildItem $TempDir -Recurse -Filter $CmdName | Select-Object -First 1 -ExpandProperty FullName
    if ($cmdPath) {
        Write-Host "  -> Inyectando Store en el sistema..."
        Start-Process $cmdPath -Verb RunAs -Wait
        Write-Host "  -> Instalacion de Store completada."
    } else {
        Write-Host "  -> No se encontro Add-Store.cmd" -ForegroundColor Red
    }
}

# --- EJECUCION 7 ---
function Install-Winget {
    if ([string]::IsNullOrWhiteSpace($BasePath)) {
        $BasePath = Join-Path $env:TEMP "WingetFullInstall"
    }
    New-Item -Path $BasePath -ItemType Directory -Force -ErrorAction Stop | Out-Null

    $VCLibsUrl  = "https://github.com/mggons93/OptimizeUpdate/raw/refs/heads/main/Programs/dependences/Microsoft.VCLibs.140.00_14.0.33519.0_x64.appx"
    $VCLibsDesktopUrl = "https://github.com/mggons93/OptimizeUpdate/raw/refs/heads/main/Programs/dependences/Microsoft.VCLibs.140.00.UWPDesktop_14.0.33728.0_x64.appx"
    $XamlUrl    = "https://github.com/microsoft/microsoft-ui-xaml/releases/download/v2.7.3/Microsoft.UI.Xaml.2.7.x64.appx"
    $RuntimeUrl = "https://github.com/mggons93/OptimizeUpdate/raw/refs/heads/main/Programs/dependences/Microsoft.WindowsAppRuntime.1.8_8000.616.304.0_x64.appx"
    $MinimumRuntimeVersion = [version]"8000.616.304.0"
    $MinimumVCLibsVersion = [version]"14.0.33519.0"
    $MinimumVCLibsDesktopVersion = [version]"14.0.33728.0"
    
    $VCLibsPath = "$BasePath\VCLibs.appx"
    $VCLibsDesktopPath = "$BasePath\VCLibs.UWPDesktop.appx"
    $XamlPath   = "$BasePath\UI.Xaml.appx"
    $RuntimePath = "$BasePath\WindowsAppRuntime.appx"
    $WingetPath = "$BasePath\Winget.msixbundle"

    Write-Host "  -> Consultando la ultima version de Winget en GitHub..."
    try {
        $githubRelease = Invoke-RestMethod `
            -Uri "https://api.github.com/repos/microsoft/winget-cli/releases/latest" `
            -Headers @{ "User-Agent" = "PowerShell" } `
            -ErrorAction Stop
        $asset = $githubRelease.assets |
            Where-Object { $_.name -match "\.msixbundle$" } |
            Select-Object -First 1
        $WingetUrl = $asset.browser_download_url
        $assetDigest = [string]$asset.digest
        $serverVersionText = [regex]::Match(
            [string]$githubRelease.tag_name,
            '\d+(?:\.\d+){1,3}'
        ).Value

        if (-not $WingetUrl) { throw "No se encontro .msixbundle." }
        if ($assetDigest -notmatch '^sha256:([A-Fa-f0-9]{64})$') {
            throw "GitHub no proporciono un digest SHA-256 valido para el .msixbundle."
        }
        $expectedSha256 = $matches[1].ToUpperInvariant()
        if (-not $serverVersionText) { throw "Version de release invalida: $($githubRelease.tag_name)" }
        $serverVersion = [version]$serverVersionText
        Write-Host "  -> Version encontrada en GitHub: $serverVersion | SHA-256 publicado: $expectedSha256"
    } catch {
        Write-Host "  -> Error obteniendo o interpretando la release de Winget: $($_.Exception.Message)" -ForegroundColor Red
        throw
    }

    $installedPackage = Get-AppxPackage -AllUsers -Name "Microsoft.DesktopAppInstaller" -ErrorAction SilentlyContinue |
        Sort-Object { [version]$_.Version } -Descending |
        Select-Object -First 1
    $wingetCommand = Get-Command winget -ErrorAction SilentlyContinue
    $installedVersion = [version]"0.0.0"
    $commandVersion = $null

    if ($installedPackage) {
        try {
            $installedVersion = [version]$installedPackage.Version
        } catch {
            Write-Host "  -> No se pudo interpretar la version del paquete instalado: $($installedPackage.Version)" -ForegroundColor Yellow
        }
    }

    if ($wingetCommand) {
        try {
            $versionOutput = (& $wingetCommand.Source --version 2>$null | Out-String).Trim()
            $versionText = [regex]::Match($versionOutput, '\d+(?:\.\d+){1,3}').Value
            if ($versionText) {
                $commandVersion = [version]$versionText
            }
        } catch {
            Write-Host "  -> No se pudo consultar winget --version: $($_.Exception.Message)" -ForegroundColor Yellow
        }
    }

    $commandVersionText = if ($null -ne $commandVersion) { $commandVersion } else { "no detectada" }
    Write-Host "  -> Version del paquete instalada: $installedVersion | Version del comando: $commandVersionText | Version publicada: $serverVersion"
    if ($installedPackage -and $installedVersion -ge $serverVersion) {
        Write-Host "  -> Winget ya esta actualizado (o la version local es mas reciente)."
        return
    }

    if ($installedPackage -or $wingetCommand) {
        Write-Host "  -> Winget esta desactualizado. Se instalara la version $serverVersion..."
    } else {
        Write-Host "  -> Winget no detectado. Instalando dependencias..."
    }

    try {
        # Instalar primero los dos frameworks VCLibs requeridos.
        $vclibsPackages = @(
            @{
                Name = "Microsoft.VCLibs.140.00"
                Url = $VCLibsUrl
                Path = $VCLibsPath
                MinimumVersion = $MinimumVCLibsVersion
            },
            @{
                Name = "Microsoft.VCLibs.140.00.UWPDesktop"
                Url = $VCLibsDesktopUrl
                Path = $VCLibsDesktopPath
                MinimumVersion = $MinimumVCLibsDesktopVersion
            }
        )

        foreach ($vclibs in $vclibsPackages) {
            $installedVCLibs = Get-AppxPackage -AllUsers -Name $vclibs.Name -ErrorAction SilentlyContinue |
                Where-Object { $_.Architecture -in @("X64", "Neutral") } |
                Sort-Object { [version]$_.Version } -Descending |
                Select-Object -First 1
            $installedVCLibsVersion = if ($installedVCLibs) { [version]$installedVCLibs.Version } else { [version]"0.0.0" }

            if ($installedVCLibsVersion -lt $vclibs.MinimumVersion) {
                Write-Host "     - Instalando $($vclibs.Name) $($vclibs.MinimumVersion)..."
                Invoke-WebRequest $vclibs.Url -OutFile $vclibs.Path -UseBasicParsing -ErrorAction Stop
                if (-not (Test-Path -LiteralPath $vclibs.Path) -or (Get-Item -LiteralPath $vclibs.Path).Length -eq 0) {
                    throw "La descarga de $($vclibs.Name) esta vacia o no existe."
                }
                Add-AppxPackage -Path $vclibs.Path -ErrorAction Stop

                $installedVCLibs = Get-AppxPackage -AllUsers -Name $vclibs.Name -ErrorAction SilentlyContinue |
                    Where-Object { $_.Architecture -in @("X64", "Neutral") } |
                    Sort-Object { [version]$_.Version } -Descending |
                    Select-Object -First 1
                $installedVCLibsVersion = if ($installedVCLibs) { [version]$installedVCLibs.Version } else { [version]"0.0.0" }
                if ($installedVCLibsVersion -lt $vclibs.MinimumVersion) {
                    throw "$($vclibs.Name) >= $($vclibs.MinimumVersion) no aparece instalado; detectado: $installedVCLibsVersion."
                }
            } else {
                Write-Host "     - $($vclibs.Name) disponible: $installedVCLibsVersion."
            }
        }

        # UI.Xaml también es un prerequisito de algunas versiones de Winget.
        if (-not (Get-AppxPackage -AllUsers -Name "Microsoft.UI.Xaml.2.7" -ErrorAction SilentlyContinue)) {
            Write-Host "     - Descargando e instalando UI.Xaml..."
            Invoke-WebRequest $XamlUrl -OutFile $XamlPath -UseBasicParsing -ErrorAction Stop
            if (-not (Test-Path -LiteralPath $XamlPath) -or (Get-Item -LiteralPath $XamlPath).Length -eq 0) {
                throw "La descarga de UI.Xaml esta vacia o no existe."
            }
            Add-AppxPackage -Path $XamlPath -ErrorAction Stop
        }
        
        # Instalar después Windows App Runtime 1.8 requerido por Winget.
        $runtimePackage = Get-AppxPackage -AllUsers -Name "Microsoft.WindowsAppRuntime.1.8" -ErrorAction SilentlyContinue |
            Where-Object { $_.Architecture -in @("X64", "Neutral") } |
            Sort-Object { [version]$_.Version } -Descending |
            Select-Object -First 1
        $runtimeVersion = if ($runtimePackage) { [version]$runtimePackage.Version } else { [version]"0.0.0" }

        if ($runtimeVersion -lt $MinimumRuntimeVersion) {
            try {
                Write-Host "     - Windows App Runtime 1.8 requerido >= $MinimumRuntimeVersion; instalado: $runtimeVersion."
                Write-Host "     - Descargando e instalando Windows App Runtime 1.8..."
                Invoke-WebRequest $RuntimeUrl -OutFile $RuntimePath -UseBasicParsing -ErrorAction Stop
                if (-not (Test-Path -LiteralPath $RuntimePath) -or (Get-Item -LiteralPath $RuntimePath).Length -eq 0) {
                    throw "La descarga de Windows App Runtime esta vacia o no existe."
                }
                Add-AppxPackage -Path $RuntimePath -ErrorAction Stop
                $runtimePackage = Get-AppxPackage -AllUsers -Name "Microsoft.WindowsAppRuntime.1.8" -ErrorAction SilentlyContinue |
                    Where-Object { $_.Architecture -in @("X64", "Neutral") } |
                    Sort-Object { [version]$_.Version } -Descending |
                    Select-Object -First 1
                $runtimeVersion = if ($runtimePackage) { [version]$runtimePackage.Version } else { [version]"0.0.0" }
                if ($runtimeVersion -lt $MinimumRuntimeVersion) {
                    throw "Tras ejecutar el instalador, Windows App Runtime 1.8 >= $MinimumRuntimeVersion no aparece instalado; detectado: $runtimeVersion."
                }
                Write-Host "     - Windows App Runtime instalado: $runtimeVersion."
            }
            catch {
                Write-Host "     - Windows App Runtime no se pudo instalar: $($_.Exception.Message)" -ForegroundColor Yellow
                Write-Host "     - Se intentara instalar Winget de todos modos." -ForegroundColor Yellow
            }
        } else {
            Write-Host "     - Windows App Runtime disponible: $runtimeVersion."
        }

        # Descargar e instalar Winget
        Write-Host "  -> Descargando e instalando Winget $serverVersion..."
        Invoke-WebRequest $WingetUrl -OutFile $WingetPath -UseBasicParsing -ErrorAction Stop
        if (-not (Test-Path -LiteralPath $WingetPath) -or (Get-Item -LiteralPath $WingetPath).Length -eq 0) {
            throw "La descarga de Winget esta vacia o no existe."
        }

        $actualSha256 = (Get-FileHash -LiteralPath $WingetPath -Algorithm SHA256 -ErrorAction Stop).Hash.ToUpperInvariant()
        if ($actualSha256 -ne $expectedSha256) {
            throw "SHA-256 no coincide. Esperado: $expectedSha256; descargado: $actualSha256. No se instalará el paquete."
        }
        Write-Host "  -> SHA-256 verificado: $actualSha256"

        try {
            Add-AppxPackage -Path $WingetPath -ForceApplicationShutdown -ErrorAction Stop
        }
        catch {
            $appxError = $_.Exception.Message
            if ($appxError -match '(?i)0x80073CF3|Microsoft\.WindowsAppRuntime\.1\.8|framework') {
                $detectedRuntimeVersion = if ($runtimePackage) { $runtimePackage.Version } else { "no detectado" }
                throw "Windows rechazo Winget por una dependencia faltante o incompatible. Se requiere Microsoft.WindowsAppRuntime.1.8 >= $MinimumRuntimeVersion; detectado: $detectedRuntimeVersion. Error original: $appxError"
            }
            throw
        }

        $installedPackage = Get-AppxPackage -AllUsers -Name "Microsoft.DesktopAppInstaller" -ErrorAction SilentlyContinue |
            Sort-Object { [version]$_.Version } -Descending |
            Select-Object -First 1
        if (-not $installedPackage) {
            throw "Add-AppxPackage termino, pero Microsoft.DesktopAppInstaller no aparece instalado."
        }

        $installedVersion = [version]$installedPackage.Version
        if ($installedVersion -lt $serverVersion) {
            throw "La version instalada ($installedVersion) es inferior a la publicada ($serverVersion)."
        }

        Write-Host "  -> Winget verificado correctamente. Version instalada: $installedVersion"
    }
    catch {
        Write-Host "  -> Error instalando o verificando Winget: $($_.Exception.Message)" -ForegroundColor Red
        throw
    }
}

# --- EJECUCION 8 ---
function Get-WindowsActivationStatus {
    $licenseStatus = (Get-CimInstance -Query "SELECT LicenseStatus FROM SoftwareLicensingProduct WHERE PartialProductKey IS NOT NULL AND LicenseFamily IS NOT NULL").LicenseStatus
    return $licenseStatus -eq 1
}

function Enable-WindowsActivation {
    $url = "https://raw.githubusercontent.com/%blank%massgravel/Microsoft-%blank%Activation-Scripts/refs/%blank%heads/master/MAS/All-In-%blank%One-Version-KL/MAS_AIO.%blank%cmd"
    $url = $url -replace "%blank%", ""
    $outputPath1 = "$env:TEMP\O%blank%hook_Acti%blank%vation_AI%blank%O.cmd"
    $outputPath1 = $outputPath1 -replace "%blank%", ""

    #Write-Host "  -> Descargando y ejecutando Activacion..."
    Invoke-WebRequest -Uri $url -OutFile $outputPath1 -UseBasicParsing | Out-Null
    Start-Process -FilePath $outputPath1 -ArgumentList "/HWID" -WindowStyle Hidden -Wait
    Remove-Item -Path $outputPath1 -Force
}

function Invoke-WindowsActivation {
    $restartAfterActivation = $false

    # Verificar si Windows esta activado
    if (Get-WindowsActivationStatus) {
        Write-Host "  -> Windows ya esta activado."
        $restartAfterActivation = $true
    } else {
        Write-Host "  -> Windows no esta activado. Intentando activar..."
        Start-Sleep -Seconds 5
        Enable-WindowsActivation
        
        # Verificar nuevamente despues de intentar activar
        if (Get-WindowsActivationStatus) {
            Write-Host "  -> Windows ha sido activado exitosamente." -ForegroundColor Green
            $restartAfterActivation = $true
        } else {
            Write-Host "  -> La activacion de Windows ha fallado. Verifica la conexion a internet." -ForegroundColor Red
        }
    }

    if ($restartAfterActivation) {
        Write-Host "  -> Reiniciando Windows en 5 segundos..."
        Start-Sleep -Seconds 5
        Restart-Computer -Force
    }
}
###############################################################################################
# INICIO DEL SCRIPT
###############################################################################################
Start-Execution

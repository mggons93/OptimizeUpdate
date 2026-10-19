function Test-Admin {
    $currentIdentity = [Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = New-Object Security.Principal.WindowsPrincipal($currentIdentity)
    return $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

# Auto-elevaci?n
if (-not (Test-Admin)) {
    $scriptPath = $MyInvocation.MyCommand.Path
    Start-Process powershell -ArgumentList "-NoProfile -ExecutionPolicy Bypass -File `"$scriptPath`"" -Verb RunAs
    return
}

# Deshabilitar WSAIFabricSvc
Set-Service -Name "WSAIFabricSvc" -StartupType Disabled
Stop-Service -Name "WSAIFabricSvc"

# Deshabilitar TapiSrv
Set-Service -Name "TapiSrv" -StartupType Disabled
Stop-Service -Name "TapiSrv"

# Deshabilitar SCardSvr
Set-Service -Name "SCardSvr" -StartupType Disabled
Stop-Service -Name "SCardSvr"

# Deshabilitar smphost
Set-Service -Name "smphost" -StartupType Disabled
Stop-Service -Name "smphost"

# Deshabilitar PhoneSvc
Set-Service -Name "PhoneSvc" -StartupType Disabled
Stop-Service -Name "PhoneSvc"

# Verificar si Checkpoint-Computer est? disponible
if (-not (Get-Command Checkpoint-Computer -ErrorAction SilentlyContinue)) {
    Write-Host "Checkpoint-Computer no est? disponible en este sistema." -ForegroundColor Red
    return
}

# Iniciar y habilitar servicios necesarios
Set-Service -Name "VSS" -StartupType Manual -ErrorAction SilentlyContinue
Start-Service -Name "VSS" -ErrorAction SilentlyContinue

Enable-ComputerRestore -Drive "C:\"

# ============================================
#   FORZAR RUTA FIJA PARA EL LOG
# ============================================
$scriptDirectory = "C:\Windows\Setup\Scripts"

# Crear carpeta si no existe
								
if (-not (Test-Path $scriptDirectory)) {
    New-Item -Path $scriptDirectory -ItemType Directory -Force | Out-Null
}

$logFile = Join-Path $scriptDirectory "Restauracion.log"

# Crear encabezado si el archivo no existe
if (-not (Test-Path $logFile)) {
    Add-Content -Path $logFile -Value "===== Registro de creaci?n de punto de restauraci?n ====="
}

# ============================================

Write-Host "Iniciando creaci?n autom?tica de un punto de restauraci?n del sistema..." -ForegroundColor Cyan

$timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
$logEntry = "[$timestamp] Iniciando creaci?n de punto de restauraci?n..."

# Detectar letra de la unidad donde est&#225; instalado Windows de forma robusta
function Get-WindowsDriveLetter {
    # Devuelve el drive letter donde est&#225; instalado Windows (p. ej. 'C'), o $null.
    # Estrategia:
    # 1. Revisar env:SystemRoot / env:WinDir
    # 2. Leer registro HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\SystemRoot
    # 3. Consultar WMI/CIM Win32_OperatingSystem.SystemDirectory
    # 4. Buscar en PSDrive la carpeta Windows\System32

    # 1) Env vars
    try {
        if ($env:SystemRoot) {
            $sr = $env:SystemRoot
            if (Test-Path $sr) { return ([IO.Path]::GetPathRoot((Get-Item $sr).FullName)).TrimEnd(':') }
            # some cases env may be like C:\Windows\System32 - normalize
            if ($sr -match '^[A-Za-z]:') { return $sr.Substring(0,1) }
        }
        if ($env:WinDir) {
            $wd = $env:WinDir
            if (Test-Path $wd) { return ([IO.Path]::GetPathRoot((Get-Item $wd).FullName)).TrimEnd(':') }
            if ($wd -match '^[A-Za-z]:') { return $wd.Substring(0,1) }
        }
    } catch { }

    # 2) Registry
    try {

        $reg = Get-ItemProperty -Path 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion' -Name 'SystemRoot' -ErrorAction SilentlyContinue
        if ($reg -and $reg.SystemRoot) {
            $sr = $reg.SystemRoot
            # Expand any environment variables
            $expanded = ([Environment]::ExpandEnvironmentVariables($sr))
            if (Test-Path $expanded) { return ([IO.Path]::GetPathRoot((Get-Item $expanded).FullName)).TrimEnd(':') }
            if ($expanded -match '^[A-Za-z]:') { return $expanded.Substring(0,1) }
        }
    } catch { }

    # 3) WMI / CIM
    try {
        $os = Get-CimInstance -ClassName Win32_OperatingSystem -ErrorAction SilentlyContinue
        if ($os -and $os.SystemDirectory) {
            $sd = $os.SystemDirectory
            if (Test-Path $sd) { return ([IO.Path]::GetPathRoot((Get-Item $sd).FullName)).TrimEnd(':') }
            if ($sd -match '^[A-Za-z]:') { return $sd.Substring(0,1) }
        }
    } catch { }

    # 4) Buscar unidad que contenga Windows\System32
    try {
        $drive = Get-PSDrive -PSProvider FileSystem | Where-Object {
            try { Test-Path (Join-Path $_.Root 'Windows\System32') } catch { $false }
        } | Select-Object -First 1
        if ($drive) { return $drive.Name }
    } catch { }

    return $null
}

$mediaType = "No identificado"
try {
    $driveLetter = Get-WindowsDriveLetter
    # Normalizar a una sola letra (C en vez de C:\)
    if ($driveLetter -match '^[A-Za-z]:') { $driveLetter = $driveLetter.Substring(0,1) }
    if ($driveLetter -match '^[A-Za-z]$') { $driveLetter = $driveLetter.ToUpper() }
    Write-Host "driveLetter = $driveLetter"
    $logEntry += " | driveLetter: $driveLetter"
        # Intentar mapear la unidad l&#243;gica a disco f&#237;sico v&#237;a asociaciones WMI/CIM
        try {
            $ld = Get-CimInstance -ClassName Win32_LogicalDisk -Filter "DeviceID = '$($driveLetter):'" -ErrorAction SilentlyContinue
            if ($ld) {
                $parts = Get-CimAssociatedInstance -InputObject $ld -Association Win32_LogicalDiskToPartition -ErrorAction SilentlyContinue
                if ($parts) {
                    foreach ($p in $parts) {
                        $drives = Get-CimAssociatedInstance -InputObject $p -Association Win32_DiskDriveToDiskPartition -ErrorAction SilentlyContinue
                        if ($drives) {
                            $driveObj = $drives | Select-Object -First 1
                            if ($driveObj.Index -ne $null) {
                                $diskNumber = $driveObj.Index
                                Write-Host "WMI mapping result: DiskDrive Index = $diskNumber, Model=$($driveObj.Model)"
                                $logEntry += " | WmiMappedDiskIndex: $diskNumber Model: $($driveObj.Model)"
                                break
                            }
                        }
                    }
                }
            }
        } catch {
            # ignore mapping errors
        }
        if ($driveLetter) {
            # Prefer Get-Disk (provides MediaType). If not available or returns Unspecified, try fallback methods.
            try {
                Write-Host "Obteniendo particion y numero de disco para $driveLetter..."
                $partition = Get-Partition -DriveLetter $driveLetter -ErrorAction Stop
                $diskNumber = $partition.DiskNumber
                Write-Host "partition.DiskNumber = $diskNumber"
                $logEntry += " | DiskNumber: $diskNumber"

                $gd = Get-Disk -Number $diskNumber -ErrorAction Stop
                if ($gd -and $gd.MediaType) {
                    $mt = $gd.MediaType.ToString()
                    Write-Host "Get-Disk MediaType raw: '$mt'"
                    $logEntry += " | GetDiskMediaTypeRaw: $mt"
                    if ($mt -match '(?i)SSD|NVME') { $mediaType = 'SSD' } 
                    elseif ($mt -match '(?i)HDD|FIXED|HARD|ROTATIONAL') { $mediaType = 'HDD' } 
                    else { $mediaType = $mt }
                }
            } catch {
                # ignore and try fallback
            }
            if ($mediaType -eq "No identificado" -or [string]::IsNullOrEmpty($mediaType)) {
                try {
                    # Fallback: try Get-PhysicalDisk and match by FriendlyName or UniqueId if possible
                    $phys = Get-PhysicalDisk -ErrorAction SilentlyContinue
                    if ($phys) {
                        # Attempt coarse match: if only one physical disk, take its MediaType and normalize
                        if ($phys.Count -eq 1) { 
                            $pmt = $phys[0].MediaType
                            if ($pmt -match '(?i)SSD|NVME') { $mediaType = 'SSD' } 
                            elseif ($pmt -match '(?i)HDD|FIXED|HARD|ROTATIONAL') { $mediaType = 'HDD' } 
                            else { $mediaType = $pmt }
                        }
                    }
                } catch {
                    # final fallback ignored
                }
            }

        # Si aún no se identifica, intentar heur&#237;stica adicional usando Win32_DiskDrive (RotationRate/InterfaceType)
        if ($mediaType -eq "No identificado" -and $driveLetter) {
            try {
                if ($diskNumber -ne $null) {
                    $wdd = Get-CimInstance -ClassName Win32_DiskDrive -Filter "Index = $diskNumber" -ErrorAction SilentlyContinue
                    if ($wdd) {
                            Write-Host "Win32_DiskDrive found: Index=$($wdd.Index) Model='$($wdd.Model)' InterfaceType='$($wdd.InterfaceType)' RotationRate='$($wdd.RotationRate)'"
                            $logEntry += " | Win32DiskDrive: Index=$($wdd.Index) Model=$($wdd.Model) Interface=$($wdd.InterfaceType) RotationRate=$($wdd.RotationRate)"
                        # Primero, intentar por modelo (muchas controladoras reportan InterfaceType/RotationRate inconsistentes)
                        $modelStr = ($wdd.Model | Out-String).Trim().ToUpper()
                        if ($modelStr -match '(SSD|NVME|M2|M\.2|ADATA|SAMSUNG|CRUCIAL|KINGSTON|INTEL|SKHYNIX|PHISON|970|980|SU630|SU8|PM9|SN)') {
                            $mediaType = "SSD"
                        } elseif ($modelStr -match '(WD|WDC|TOSHIBA|ST|SEAGATE|HITACHI|HGST|WD10|WD40|WD60|WD80|WD50)') {
                            $mediaType = "HDD"
                        } else {
                            # RotationRate: 0 => SSD (no rotaci&#243;n), >0 => HDD
                            if ($wdd.RotationRate -ne $null) {
                                if ([int]$wdd.RotationRate -eq 0) { $mediaType = "SSD" } else { $mediaType = "HDD" }
                            } else {
                                # Use InterfaceType as hint (NVMe likely SSD, SATA/IDE likely HDD)
                                $it = ($wdd.InterfaceType | Out-String).Trim()
                                if ($it -match '(?i)NVME|SSD') { $mediaType = "SSD" }
                                elseif ($it -match '(?i)IDE|SATA|ATAPI|SCSI') { $mediaType = "HDD" }
                            }
                        }
                        if ($mediaType -ne "No identificado") { $logEntry += " | HeuristicaDiskDrive: Interface=$it RotationRate=$($wdd.RotationRate) Model=$($wdd.Model)" }
                    }
                }
            } catch {
                # ignore
            }
        }

        # Si aún no identificado, forzar heur&#237;stica global buscando modelos SSD en todos los discos
        if ($mediaType -eq "No identificado") {
            try {
                $allDrives = Get-CimInstance Win32_DiskDrive -ErrorAction SilentlyContinue
                foreach ($d in $allDrives) {
                    $m = ($d.Model | Out-String).Trim().ToUpper()
                    if ($m -match '(SSD|NVME|M2|M\.2|ADATA|SAMSUNG|CRUCIAL|KINGSTON|INTEL|SKHYNIX|PHISON|970|980|SU630|SU8|PM9|SN)') {
                        # ignore obvious external USB drives
                        $it = ($d.InterfaceType | Out-String).Trim()
                        if ($it -match '(?i)USB|USB') { continue }
                        $mediaType = "SSD"
                        $logEntry += " | ForcedByModel: $($d.Model) (Interface=$it)"
                        break
                    }
                    if ($m -match '(WD|WDC|TOSHIBA|ST|SEAGATE|HITACHI|HGST|WD10|WD40|WD60|WD80|WD50)') {
                        $it = ($d.InterfaceType | Out-String).Trim()
                        if ($it -match '(?i)USB') { continue }
                        $mediaType = "HDD"
                        $logEntry += " | ForcedByModel: $($d.Model) (Interface=$it)"
                        break
                    }
                }
            } catch {
                # ignore
            }
        }
    }
} catch {
    # Si Get-Partition falla, dejamos mediaType en No identificado
    $mediaType = "No identificado"
}

# Determinar la ruta completa de Windows para registrar
$windowsPath = $null
try {
    if ($env:SystemRoot -and (Test-Path $env:SystemRoot)) { $windowsPath = (Get-Item $env:SystemRoot).FullName }
    elseif ($env:WinDir -and (Test-Path $env:WinDir)) { $windowsPath = (Get-Item $env:WinDir).FullName }
    else {
        try {
            $reg = Get-ItemProperty -Path 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion' -Name 'SystemRoot' -ErrorAction SilentlyContinue
            if ($reg -and $reg.SystemRoot) { $expanded = [Environment]::ExpandEnvironmentVariables($reg.SystemRoot); if (Test-Path $expanded) { $windowsPath = (Get-Item $expanded).FullName } }
        } catch { }
        if (-not $windowsPath -and $driveLetter) {
            $cand = "$driveLetter`:\Windows"
            if (Test-Path $cand) { $windowsPath = (Get-Item $cand).FullName }
        }
        if (-not $windowsPath) {
            try { $os = Get-CimInstance -ClassName Win32_OperatingSystem -ErrorAction SilentlyContinue; if ($os -and $os.SystemDirectory -and (Test-Path $os.SystemDirectory)) { $windowsPath = (Get-Item $os.SystemDirectory).FullName } } catch { }
        }
    }
} catch { }

if ($windowsPath) { Write-Host "Ruta de Windows detectada: $windowsPath"; $logEntry += " | WindowsPath: $windowsPath" } else { Write-Host "No se pudo determinar la ruta completa de Windows." -ForegroundColor Yellow; $logEntry += " | WindowsPath: No identificado" }

# Mostrar y loguear el valor final de mediaType para diagn&#243;stico
Write-Host "mediaType final = '$mediaType'"
$logEntry += " | mediaTypeFinal: $mediaType"

switch ($mediaType) {
    "SSD" {
        Write-Host "Disco del sistema detectado: SSD"
        $logEntry += " | Disco: SSD"
        $regPath = "HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\SystemRestore"
        $regName = "SystemRestorePointCreationFrequency"

        if (-not (Test-Path $regPath)) {
            New-Item -Path $regPath -Force | Out-Null
        }

        Set-ItemProperty -Path $regPath -Name $regName -Value 0 -Type DWord
        Write-Host "Optimizaci?n aplicada correctamente."
        $logEntry += " | Optimizaci?n aplicada."
    }
    "HDD" {
        Write-Host "Disco del sistema detectado: HDD"
        $logEntry += " | Disco: HDD"
    }
    Default {
        Write-Host "No se pudo determinar si el disco es SSD o HDD. Continuando..."
        $logEntry += " | Disco: No identificado"
    }
}

$restorePointName = "OptimizacionSyA"
Write-Host "`nCreando punto de restauraci?n: $restorePointName ..." -ForegroundColor Yellow
$start = Get-Date

try {
    Checkpoint-Computer -Description $restorePointName -RestorePointType "MODIFY_SETTINGS"
    $end = Get-Date
    $duration = $end - $start
    $logEntry += " | Estado: ?xito | Duraci?n: $($duration.TotalSeconds) segundos"

    Write-Host "`nPunto de restauraci?n creado exitosamente." -ForegroundColor Green
    Write-Host "Tiempo total: $($duration.TotalSeconds) segundos." -ForegroundColor Gray
} catch {
    $logEntry += " | Estado: ERROR | Detalles: $_"
    Write-Host "`nOcurri? un error al crear el punto de restauraci?n: $_" -ForegroundColor Red
}

# Guardar log final
Add-Content -Path $logFile -Value $logEntry

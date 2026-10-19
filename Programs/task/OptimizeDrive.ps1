############################################################
# OPTIMIZAR DISCO SSD
# Compatible con Win10 / Win11 (hasta 26H2) / LTSC / IoT / PS5 / PS7
############################################################

# Requerir elevacion de privilegios (Administrador)
$isAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
if (-not $isAdmin) {
    Write-Warning "Este script requiere ejecutarse como Administrador para configurar servicios, TRIM y directivas de disco."
    exit 1
}

# No ocultar fallos: cada operaci&#243;n opcional ya debe manejar su propio error.
# El valor predeterminado de PowerShell permite ver advertencias y errores reales.

Write-Host ""
Write-Host "===== LISTADO DE DISCOS =====" -ForegroundColor Cyan

# ==========================================
# FUNCION: Deteccion robusta del disco del sistema
# ==========================================
function Get-SystemDiskInfo {
    $driveLetter = ($env:SystemDrive).TrimEnd(':')

    # Metodo 1: Modulo Storage nativo (Get-Partition -> Get-Disk)
    try {
        $part = @(Get-Partition -DriveLetter $driveLetter -ErrorAction Stop)
        $diskNumbers = @($part | Select-Object -ExpandProperty DiskNumber -Unique)
        if ($diskNumbers.Count -ne 1) {
            throw "La unidad del sistema no se pudo asociar a un único disco f&#237;sico."
        }
        $disk = Get-Disk -Number $diskNumbers[0] -ErrorAction Stop

        $mediaType = "Unknown"
        try {
            $pd = Get-PhysicalDisk | Where-Object { 
                $_.FriendlyName -eq $disk.FriendlyName -or $_.DeviceId -eq "$($disk.Number)" 
            }
            if ($pd) { $mediaType = $pd[0].MediaType }
        } catch {}

        return [PSCustomObject]@{
            Index       = $disk.Number
            Model       = $disk.FriendlyName
            BusType     = $disk.BusType.ToString()
            MediaType   = $mediaType
            Size        = $disk.Size
            SizeGB      = [math]::Round($disk.Size / 1GB, 0)
            DriveLetter = $driveLetter
        }
    } catch {}

    # Metodo 2: Extraccion de particion via WMI/CIM
    try {
        $logical = Get-CimInstance Win32_LogicalDisk -Filter "DeviceID='${driveLetter}:'" -ErrorAction Stop
        $partAssoc = Get-CimAssociatedInstance $logical -Association Win32_LogicalDiskToPartition -ErrorAction Stop
        $driveAssoc = Get-CimAssociatedInstance $partAssoc -Association Win32_DiskDriveToDiskPartition -ErrorAction Stop

        if ($driveAssoc) {
            return [PSCustomObject]@{
                Index       = $driveAssoc.Index
                Model       = $driveAssoc.Model
                BusType     = $driveAssoc.InterfaceType
                MediaType   = $driveAssoc.MediaType
                Size        = $driveAssoc.Size
                SizeGB      = [math]::Round($driveAssoc.Size / 1GB, 0)
                DriveLetter = $driveLetter
            }
        }
    } catch {}

    # No asumir que el disco 0 contiene Windows: en equipos con varios discos
    # esa suposici&#243;n podr&#237;a aplicar cambios al dispositivo equivocado.
    return $null
}

# ==========================================
# MOSTRAR DISCOS DEL EQUIPO
# ==========================================
try {
    $allDisks = @(Get-CimInstance Win32_DiskDrive -ErrorAction Stop)
} catch {
    Write-Host "No se pudo consultar la lista de discos: $($_.Exception.Message)" -ForegroundColor Red
    exit 1
}

foreach ($d in $allDisks) {
    Write-Host ""
    Write-Host "Disco #      : $($d.Index)"
    Write-Host "Modelo       : $($d.Model)"
    Write-Host "Interface    : $($d.InterfaceType)"
    Write-Host "MediaType    : $($d.MediaType)"
    Write-Host "Tamano       : $([math]::Round($d.Size / 1GB, 0)) GB"
}

# ==========================================
# IDENTIFICACION DEL DISCO DEL SISTEMA
# ==========================================
$sysDisk = Get-SystemDiskInfo

if (-not $sysDisk) {
    Write-Host ""
    Write-Host "Error: No se pudo detectar el disco del sistema." -ForegroundColor Red
    exit 1
}

Write-Host ""
Write-Host "===== DISCO DEL SISTEMA ($($sysDisk.DriveLetter):) =====" -ForegroundColor Green
Write-Host "Disco fisico : $($sysDisk.Index)"
Write-Host "Modelo       : $($sysDisk.Model)"
Write-Host "Interface    : $($sysDisk.BusType)"
Write-Host "MediaType    : $($sysDisk.MediaType)"
Write-Host "Tamano       : $($sysDisk.SizeGB) GB"
Write-Host "================================="

Write-Output "93% Completado"

# ==========================================
# EVALUACION DE TIPO DE DISCO (SSD / NVMe)
# ==========================================
# Si Windows informa MediaType/BusType como Unknown y el modelo no permite
# reconocer el SSD, cambia este valor a $true para el disco del sistema.
# En $false, el script conserva la deteccion automatica y actua con cautela.
$ForceSystemDiskSSD = $false

$isSSD = $false

# Criterio 1: Clasificacion del subsistema de almacenamiento
if ($sysDisk.MediaType -in @('SSD', 'SCM') -or $sysDisk.BusType -in @('NVMe', 'PCIe')) {
    $isSSD = $true
}

# Criterio 2: Coincidencia por modelo (cubre NVMe detras de controladoras Intel RST/SCSI)
if (-not $isSSD) {
    $ssdPatterns = "SSD|NVME|M\.2|KBG|KIOXIA|ADATA|FANXIANG|S500\s?PRO|SU[0-9]+|KINGSTON|WD GREEN|WD BLUE|WD BLACK|CRUCIAL|SAMSUNG|SK hynix|SANDISK|MICRON"
    if ($sysDisk.Model -match $ssdPatterns) {
        $isSSD = $true
    }
}

# Sobrescritura manual para SSD no identificados por el controlador o modelo.
if ($ForceSystemDiskSSD) {
    $isSSD = $true
    Write-Host "Deteccion manual: el disco del sistema se tratara como SSD." -ForegroundColor Yellow
}

# ==========================================
# OPTIMIZACION
# ==========================================
if ($isSSD) {

    Write-Host ""
    Write-Host "SSD detectado - Aplicando optimizaciones..." -ForegroundColor Cyan

    # 1. Habilitar TRIM para NTFS y ReFS (0 = Activado)
    fsutil behavior set DisableDeleteNotify 0 | Out-Null
    fsutil behavior set DisableDeleteNotify ReFS 0 | Out-Null

    # 2. ReTrim oficial mediante cmdlet nativo
    Optimize-Volume -DriveLetter $sysDisk.DriveLetter -ReTrim -ErrorAction SilentlyContinue

    Write-Output "95% Completado"

    # 3. Desactivar Hibernacion (ahorra decenas de GB y reduce escrituras en SSD)
    powercfg -h off

    # 4. Desactivar SysMain / SuperFetch (innecesario y genera escrituras constantes en SSD)
    $sysMain = Get-Service -Name SysMain -ErrorAction SilentlyContinue
    if ($sysMain) {
        Stop-Service -Name SysMain -Force -ErrorAction SilentlyContinue
        Set-Service -Name SysMain -StartupType Disabled -ErrorAction SilentlyContinue
    }

    # 5. Deshabilitar registro de fecha del ultimo acceso a archivos
    fsutil behavior set DisableLastAccess 1 | Out-Null

    # 6. Restauracion del sistema protegida para compatibilidad con LTSC e IoT
    try {
        Enable-ComputerRestore -Drive "$($sysDisk.DriveLetter):\" -ErrorAction Stop
    } catch {
        # Ignora el error si las directivas de LTSC/IoT tienen deshabilitado VSS
    }

    Write-Output "98% Completado"

    # 7. Evaluacion automatica de CompactOS
    Write-Host ""
    Write-Host "Evaluando tamano del disco..."

    if ($sysDisk.Size -le (64GB)) {
        Write-Host "Disco pequeno ($($sysDisk.SizeGB) GB) - Activando CompactOS..." -ForegroundColor Yellow

        $state = compact.exe /compactOS:query
        if ($state -notmatch "already") {
            compact.exe /compactOS:always | Out-Null
            Write-Host "CompactOS habilitado (ahorra 2-6 GB)."
        } else {
            Write-Host "CompactOS ya activo."
        }
    } else {
        Write-Host "Disco suficiente ($($sysDisk.SizeGB) GB) - No se requiere compresion."
    }

    # 8. Ocultar carpeta ODT si existe
    if (Test-Path "C:\ODT") {
        (Get-Item "C:\ODT").Attributes = "Hidden"
    }

} else {
    Write-Host ""
    Write-Host "HDD detectado - No se aplican optimizaciones exclusivas para SSD." -ForegroundColor Yellow
}

# Configurar las categor&#237;as mostradas en Disk Cleanup, incluidas las que el usuario
# dej&#243; desmarcadas. Esto puede vaciar la Papelera, borrar paquetes de controladores
# antiguos y quitar archivos de limpieza de Windows Update.
$volumeCachesPath = "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\VolumeCaches"
$cleanupCategories = @(
    "BranchCache",
    "D3D Shader Cache",
    "DirectX Shader Cache",
    "Delivery Optimization Files",
    "Device Driver Packages",
    "Downloaded Program Files",
    "Internet Cache Files",
    "Language Pack",
    "Recycle Bin",
    "Setup Log Files",
    "System error memory dump files",
    "System error minidump files",
    "Temporary Files",
    "Temporary Setup Files",
    "Temporary Sync Files",
    "Thumbnail Cache",
    "Update Cleanup",
    "Windows Error Reporting Archive Files",
    "Windows Error Reporting ArchiveFiles",
    "Windows Error Reporting Files",
    "Windows Error Reporting Queue Files",
    "Windows Error Reporting QueueReporting",
    "Windows Error Reporting System Archive Files",
    "Windows Error Reporting System ArchiveFiles",
    "Windows Error Reporting System Queue Files",
    "Windows Error Reporting System QueueReporting",
    "Windows Defender"
)

$cleanupProfile = "StateFlags0001"
$configuredCategories = 0

foreach ($category in $cleanupCategories) {
    $categoryPath = Join-Path $volumeCachesPath $category
    if (Test-Path -LiteralPath $categoryPath) {
        try {
            New-ItemProperty -LiteralPath $categoryPath -Name $cleanupProfile `
                -PropertyType DWord -Value 2 -Force -ErrorAction Stop | Out-Null
            $configuredCategories++
        } catch {
            Write-Warning "No se pudo configurar cleanmgr para '$category': $($_.Exception.Message)"
        }
    }
}

Write-Host "Iniciando limpieza amplia de archivos temporales y cachés con cleanmgr..." -ForegroundColor Cyan
try {
    if ($configuredCategories -gt 0) {
        Write-Host "Categor&#237;as seguras configuradas: $configuredCategories"
        $cleanmgrArguments = "/sagerun:1"
    } else {
        # Respaldo si esta edici&#243;n de Windows no expone las categor&#237;as del perfil.
        Write-Warning "No se encontraron categor&#237;as para el perfil; se usar&#225; la limpieza predeterminada."
        $cleanmgrArguments = "/verylowdisk"
    }

    $cleanmgr = Start-Process -FilePath "cleanmgr.exe" `
        -ArgumentList $cleanmgrArguments -WindowStyle Hidden -Wait -PassThru -ErrorAction Stop

    if ($cleanmgr.ExitCode -eq 0) {
        Write-Host "Limpieza de cleanmgr finalizada." -ForegroundColor Green
    } else {
        Write-Warning "cleanmgr termin&#243; con c&#243;digo $($cleanmgr.ExitCode)."
    }
} catch {
    Write-Warning "No se pudo ejecutar cleanmgr: $($_.Exception.Message)"
}

Write-Host ""
Write-Host "Proceso finalizado al 100%." -ForegroundColor Green

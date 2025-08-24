# Directorio TEMP
$tempDir = $env:TEMP

# Lista de archivos con sus URLs y nombres
$archivos = @(
    @{
        Url = "https://cutt.ly/JrKeZyiF"
        Nombre = "Microsoft.UI.Xaml.2.8.x64.appx"
    },
    @{
        Url = "https://download.microsoft.com/download/4/7/c/47c6134b-d61f-4024-83bd-b9c9ea951c25/Microsoft.VCLibs.x64.14.00.Desktop.appx"
        Nombre = "Microsoft.VCLibs.x64.14.00.Desktop.appx"
    },
    @{
        Url = "https://aka.ms/getwinget"
        Nombre = "WinGet.msixbundle"
    },
    @{
        Url = "https://github.com/mggons93/OptimizeUpdate/raw/refs/heads/main/MS_Store.msix"
        Nombre = "WinStore.msix"
    }
)

# Descargar archivos
foreach ($archivo in $archivos) {
    $destino = Join-Path $tempDir $archivo.Nombre
    Write-Host "Descargando $($archivo.Nombre)..."
    Invoke-WebRequest -Uri $archivo.Url -OutFile $destino
    Write-Host "Guardado en $destino"
}

# Rutas completas
$uiPath     = Join-Path $tempDir "Microsoft.UI.Xaml.2.8.x64.appx"
$vcPath     = Join-Path $tempDir "Microsoft.VCLibs.x64.14.00.Desktop.appx"
$wingetPath = Join-Path $tempDir "WinGet.msixbundle"
$storePath  = Join-Path $tempDir "WinStore.msix"

# Instalación en orden
Write-Host "Instalando Microsoft.UI.Xaml..."
Add-AppxPackage -Path $uiPath

Write-Host "Instalando Microsoft.VCLibs..."
Add-AppxPackage -Path $vcPath

Write-Host "Instalando WinGet..."
Add-AppxPackage -Path $wingetPath

Write-Host "Instalando Microsoft Store..."
Add-AppxPackage -Path $storePath

Write-Host "Todos los paquetes fueron instalados correctamente."

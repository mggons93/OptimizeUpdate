## Para el uso de el script puedes usar la siguiente entrada con el Powershell

```bash
irm https://cutt.ly/NewOptimize | iex
```

## To use the script you can use the following entry with Powershell

```bash
irm https://cutt.ly/NewOptimize | iex
```
## Para instalar solo las apps, ejecuta ek siguiente script en powershell
```bash
irm https://cutt.ly/HeOAo694 | iex
```

## To install only the apps, run the following script in powershell

```bash
irm https://cutt.ly/HeOAo694 | iex
```
```
## Upcoming updates
## Proximas actualizaciones

Vuelve la interfaz de Optimizacion y Instalacion de Apps. 29/04/20205

```
## Imagen de Muestra Optimizando Windows
<p align="center">
<a href=></a><img src="https://github.com/mggons93/OptimizeUpdate/blob/main/Optimizando.gif"/>
</p>

## Imagen de Muestra Instalando Apps
<p align="center">
<a href=></a><img src="https://github.com/mggons93/OptimizeUpdate/blob/main/Installapps.gif"/>
</p>

```
# 🧰 Script de Optimización para Windows (`optimizeoriginal.ps1`)

Este script de PowerShell está diseñado para realizar una serie de ajustes y limpiezas en el sistema operativo Windows con el objetivo de mejorar el rendimiento general.

---

## 📋 Acciones que Realiza el Script

1. Desactiva el almacenamiento reservado del sistema operativo (Reserved Storage).
2. Inicia una barra de progreso visual desde 1% hasta 100%.
3. Programa la ejecución de una aplicación externa tras reiniciar el sistema (`RunOnce`).
4. Activa el plan de energía de "Alto Rendimiento" (`Ultimate Performance`).
5. Agrega una carpeta como excepción en Windows Defender.
6. Agrega uno o varios procesos como excepción en Windows Defender.
7. Desactiva tareas programadas consideradas innecesarias.
8. Aplica configuraciones en el registro de Windows para:
    - Desactivar animaciones y efectos visuales.
    - Deshabilitar funciones no esenciales.
    - Optimizar el explorador de archivos y la interfaz.
9. Elimina archivos temporales del sistema (`C:\Windows\Temp`).
10. Elimina archivos temporales del usuario (`%temp%`).
11. Detiene servicios de actualizaciones:
    - `wuauserv` (Windows Update) Se Optimiza
    - `bits` (Transferencia Inteligente en Segundo Plano) Se Optimiza
    - `dosvc` (Optimización de Entrega) Se Optimiza
12. Se reinicia servicios de actualizaciones
13. Borra la caché de actualizaciones de Windows (`SoftwareDistribution`).
14. Realiza pausas entre operaciones críticas para asegurar su correcta aplicación.
15. Reinicia el sistema tras 5 segundos de finalizar todos los pasos.

---
```
```
# 🧰 Script de Instalacion de apps para Windows (`AprovisionandoApps.ps1`)

Script de aprovisionamiento para entornos Windows. Automatiza tareas comunes de instalación, configuración inicial y limpieza de entradas de inicio. Diseñado para ejecutarse con privilegios elevados y simplificar la preparación de un entorno de trabajo.

---

## 📋 Acciones que Realiza el Script

1. 🧹 Limpieza de entradas de inicio del registro
   - Elimina la entrada `TranslucentTB` de:
     ```
     HKCU:\Software\Microsoft\Windows\CurrentVersion\Run
     ```

2. 📦 Instalación de Winget
   - Descarga la última versión del instalador `.msixbundle` desde GitHub Releases de Microsoft.
   - Usa PowerShell para instalar el paquete de forma silenciosa.

3. 🧰 Aprovisionamiento con Winget (planificado para futuras líneas)
   - Instala TranslucentTB, una herramienta para personalizar la barra de tareas de Windows (efecto transparente o borroso).
   - Instala Windows Terminal, el nuevo terminal moderno de Microsoft compatible con PowerShell, CMD y WSL.

### 🔧 Redistribuibles de Visual C++
Instalan las librerías necesarias para ejecutar muchas aplicaciones en C++:

   - VCRedist2005x64
   - VCRedist2008x64
   - VCRedist2010x64
   - VCRedist2012x64
   - VCRedist2013x6
   - VCRedist2015x64
#### Versiones x86:
   - VCRedist2005x86
   - VCRedist2008x86
   - VCRedist2010x86
   - VCRedist2012x86
   - VCRedist2013x86
   - VCRedist2015x86
---
### 🧩 .NET Runtime
Instalan versiones necesarias de .NET para ejecutar aplicaciones modernas:

#### Solo runtime:
    - DotNetRuntime31 → .NET Core 3.1  
    - DotNetRuntime5 → .NET 5  
    - DotNetRuntime6 → .NET 6  
    - DotNetRuntime7 → .NET 7  
    - DotNetRuntime8 → .NET 8  
#### Desktop runtime:
    - DotNetDesktopRuntime31
    - DotNetDesktopRuntime5
    - DotNetDesktopRuntime6
    - DotNetDesktopRuntime7
    - DotNetDesktopRuntime8 
Permiten ejecutar aplicaciones de escritorio hechas con WinForms o WPF.

---

### 🛠️ Otras utilidades
  - VCLibsDesktop14  
  Instala las Microsoft Visual C++ Runtime Libraries (v14), requeridas por muchas aplicaciones modernas.
  - RustDesk  
  Instala RustDesk, una alternativa libre y segura a TeamViewer para control remoto.
  - 7Zip  
  Instala el famoso compresor de archivos 7-Zip.
  - Notepadplus  
  Instala Notepad++, un editor de texto avanzado para desarrolladores.
  - Nitro PDF  
  Instala Nitro PDF, un vidor y editor de PDF avanzado.

```
## Group
<a href="https://chat.whatsapp.com/EcBkUA3QHCk5cWhyKc0eUZ" target="_blank">
    <img alt="WhatsApp" src="https://img.shields.io/badge/WhatsApp%20Group-25D366?style=for-the-badge&logo=whatsapp&logoColor=white"/>
</a>

### Donate
<a href="https://paypal.me/malagons" target="_blank"><img alt="Paypal" src="https://img.shields.io/badge/PayPal-00457C?style=for-the-badge&logo=paypal&logoColor=white" /></a>


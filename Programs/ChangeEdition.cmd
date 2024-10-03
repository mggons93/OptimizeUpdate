@echo off 
cd /d "%~dp0" && ( if exist "%temp%\getadmin.vbs" del "%temp%\getadmin.vbs" ) && fsutil dirty query %systemdrive% 1>nul 2>nul || (  echo Set UAC = CreateObject^("Shell.Application"^) : UAC.ShellExecute "cmd.exe", "/k cd ""%~sdp0"" && %~s0 %params%", "", "runas", 1 >> "%temp%\getadmin.vbs" && "%temp%\getadmin.vbs" && exit /B )
pushd "%~dp0\"
cd /d "%~dp0\"

:start
cls
ECHO **********************************
ECHO * Windows 10/11 Version Switcher *
ECHO **********************************
ECHO 1. Windows 10/11 Pro
ECHO 2. Windows 10/11 Pro VL
ECHO 3. Windows 10/11 Education VL
ECHO 4. Windows 10/11 Enterprise VL
ECHO 5. Windows 10/11 Enterprise G
ECHO 6. Windows 10/11 Enterprise N
ECHO 7. Windows 10/11 Pro Education
ECHO 8. Windows 10/11 Pro for Workstations
ECHO 9. Exit
ECHO.

set choice=
set /p choice=Select Version: 

if not '%choice%'=='' set choice=%choice:~0,1%
if '%choice%'=='1' goto to_pro
if '%choice%'=='2' goto to_pro_vl
if '%choice%'=='3' goto to_edu_vl
if '%choice%'=='4' goto to_ent_vl
if '%choice%'=='5' goto to_ent_g
if '%choice%'=='6' goto to_ent_n
if '%choice%'=='7' goto to_pro_edu
if '%choice%'=='8' goto to_pro_ws
if '%choice%'=='9' goto end
goto start

:to_pro
cscript.exe %windir%\system32\slmgr.vbs /rilc
cscript.exe %windir%\system32\slmgr.vbs /upk >nul 2>&1
cscript.exe %windir%\system32\slmgr.vbs /ckms >nul 2>&1
cscript.exe %windir%\system32\slmgr.vbs /cpky >nul 2>&1
cscript.exe %windir%\system32\slmgr.vbs /ipk VK7JG-NPHTM-C97JM-9MPGT-3V66T
changepk /ProductKey VK7JG-NPHTM-C97JM-9MPGT-3V66T
goto finish

:to_pro_vl
cscript.exe %windir%\system32\slmgr.vbs /rilc
cscript.exe %windir%\system32\slmgr.vbs /upk >nul 2>&1
cscript.exe %windir%\system32\slmgr.vbs /ckms >nul 2>&1
cscript.exe %windir%\system32\slmgr.vbs /cpky >nul 2>&1
cscript.exe %windir%\system32\slmgr.vbs /ipk W269N-WFGWX-YVC9B-4J6C9-T83GX
changepk /ProductKey W269N-WFGWX-YVC9B-4J6C9-T83GX
goto finish

:to_edu_vl
cscript.exe %windir%\system32\slmgr.vbs /rilc
cscript.exe %windir%\system32\slmgr.vbs /upk >nul 2>&1
cscript.exe %windir%\system32\slmgr.vbs /ckms >nul 2>&1
cscript.exe %windir%\system32\slmgr.vbs /cpky >nul 2>&1
cscript.exe %windir%\system32\slmgr.vbs /ipk NW6C2-QMPVW-D7KKK-3GKT6-VCFB2
changepk /ProductKey NW6C2-QMPVW-D7KKK-3GKT6-VCFB2
goto finish

:to_ent_vl
cscript.exe %windir%\system32\slmgr.vbs /rilc
cscript.exe %windir%\system32\slmgr.vbs /upk >nul 2>&1
cscript.exe %windir%\system32\slmgr.vbs /ckms >nul 2>&1
cscript.exe %windir%\system32\slmgr.vbs /cpky >nul 2>&1
cscript.exe %windir%\system32\slmgr.vbs /ipk NPPR9-FWDCX-D2C8J-H872K-2YT43
changepk /ProductKey NPPR9-FWDCX-D2C8J-H872K-2YT43
goto finish

:to_ent_g
cscript.exe %windir%\system32\slmgr.vbs /rilc
cscript.exe %windir%\system32\slmgr.vbs /upk >nul 2>&1
cscript.exe %windir%\system32\slmgr.vbs /ckms >nul 2>&1
cscript.exe %windir%\system32\slmgr.vbs /cpky >nul 2>&1
cscript.exe %windir%\system32\slmgr.vbs /ipk YYVX9-NTFWV-6MDM3-9PT4T-4M68B
changepk /ProductKey YYVX9-NTFWV-6MDM3-9PT4T-4M68B
goto finish

:to_ent_n
cscript.exe %windir%\system32\slmgr.vbs /rilc
cscript.exe %windir%\system32\slmgr.vbs /upk >nul 2>&1
cscript.exe %windir%\system32\slmgr.vbs /ckms >nul 2>&1
cscript.exe %windir%\system32\slmgr.vbs /cpky >nul 2>&1
cscript.exe %windir%\system32\slmgr.vbs /ipk DPH2V-TTNVB-4X9Q3-TJR4H-KHJW4
changepk /ProductKey DPH2V-TTNVB-4X9Q3-TJR4H-KHJW4
goto finish

:to_pro_edu
cscript.exe %windir%\system32\slmgr.vbs /rilc
cscript.exe %windir%\system32\slmgr.vbs /upk >nul 2>&1
cscript.exe %windir%\system32\slmgr.vbs /ckms >nul 2>&1
cscript.exe %windir%\system32\slmgr.vbs /cpky >nul 2>&1
cscript.exe %windir%\system32\slmgr.vbs /ipk 6TP4R-GNPTD-KYYHQ-7B7DP-J447Y
changepk /ProductKey 6TP4R-GNPTD-KYYHQ-7B7DP-J447Y
goto finish

:to_pro_ws
cscript.exe %windir%\system32\slmgr.vbs /rilc
cscript.exe %windir%\system32\slmgr.vbs /upk >nul 2>&1
cscript.exe %windir%\system32\slmgr.vbs /ckms >nul 2>&1
cscript.exe %windir%\system32\slmgr.vbs /cpky >nul 2>&1
cscript.exe %windir%\system32\slmgr.vbs /ipk NRG8B-VKK3Q-CXVCJ-9G2XF-6Q84J
changepk /ProductKey NRG8B-VKK3Q-CXVCJ-9G2XF-6Q84J
goto finish

:finish
ECHO.
ECHO Switched Successfully
shutdown -r -t 30

:end
ECHO.
exit
@echo off
setlocal
rem Author: https://github.com/vadlike
set SCRIPT_DIR=%~dp0
set PS_EXE=%SystemRoot%\System32\WindowsPowerShell\v1.0\powershell.exe
if not "%~1"=="" goto run_args

:menu
cls
echo NanoKVM USB Graphic Driver Tool
echo Author: vadlike ^(https://github.com/vadlike^)
echo.
echo 1. Show driver status
echo 2. Install signed driver as administrator
echo 3. Remove NanoKVM driver as administrator
echo 4. Export current signer certificate
echo 5. Show help
echo 6. Exit
echo.
set /p CHOICE=Select an option: 

if "%CHOICE%"=="1" goto status
if "%CHOICE%"=="2" goto install_existing
if "%CHOICE%"=="3" goto remove_driver
if "%CHOICE%"=="4" goto extract_cert
if "%CHOICE%"=="5" goto help
if "%CHOICE%"=="6" goto end

echo.
echo Invalid choice.
pause
goto menu

:status
call :run -Action status
goto pause_and_menu

:install_existing
call :run_elevated "%SCRIPT_DIR%tools\install-driver-elevated.ps1"
goto pause_and_menu

:remove_driver
call :run_elevated "%SCRIPT_DIR%tools\remove-driver-elevated.ps1"
goto pause_and_menu

:extract_cert
call :run -Action extract-cert
goto pause_and_menu

:help
call :run -Action help
goto pause_and_menu

:run_args
call :run %*
goto end

:run
"%PS_EXE%" -NoLogo -NoProfile -ExecutionPolicy Bypass -File "%SCRIPT_DIR%tools\driver-tool.ps1" %*
exit /b %ERRORLEVEL%

:run_elevated
"%PS_EXE%" -NoLogo -NoProfile -ExecutionPolicy Bypass -Command "Start-Process -Verb RunAs -Wait -FilePath '%PS_EXE%' -ArgumentList '-NoLogo','-NoProfile','-ExecutionPolicy','Bypass','-File','\"%~1\"'"
exit /b %ERRORLEVEL%

:pause_and_menu
echo.
pause
goto menu

:end
exit /b %ERRORLEVEL%

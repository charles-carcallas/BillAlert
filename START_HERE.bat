@echo off
title BillAlert - 1-Click Team Defense & Code Explorer
color 0B

echo ====================================================================
echo                 BILLALERT: 1-CLICK TEAM EXPLORER
echo ====================================================================
echo.

:: 1. Detect Directory
set "CURRENT_DIR=%~dp0"
if "%CURRENT_DIR:~-1%"=="\" set "CURRENT_DIR=%CURRENT_DIR:~0,-1%"

echo [*] Workspace location:
echo     "%CURRENT_DIR%"
echo.

:: 2. Launch VS Code
echo [*] Launching VS Code with the BillAlert repository...
where code >nul 2>nul
if %errorlevel% equ 0 (
    start "" code "%CURRENT_DIR%"
    echo [+] VS Code launched successfully!
) else (
    echo [!] Notice: 'code' command is not in your system PATH.
    echo     You can open VS Code manually: File -^> Open Folder -^> Select this folder.
)
echo.

:: 3. Automatically Launch Defense Hub Portal
echo [*] Automatically opening Defense Hub Portal in your browser...
if exist "%CURRENT_DIR%\INDEX_DEFENSE_HUB.html" (
    start "" "%CURRENT_DIR%\INDEX_DEFENSE_HUB.html"
    echo [+] INDEX_DEFENSE_HUB.html opened in default browser!
) else (
    echo [!] Warning: Could not find INDEX_DEFENSE_HUB.html.
)
echo.

echo ====================================================================
echo   SUCCESS! The Defense Hub is open in your browser, and VS Code is ready.
echo.
echo   * Select your role on screen (Meter Reader, Admin, Cashier, Consumer)
echo     to launch your personal defense dossier!
echo   * Clicking ANY code button will jump directly to that exact line
echo     in VS Code on YOUR laptop!
echo   * No Flutter, Dart, or Android Studio required to explore!
echo ====================================================================
echo.
pause

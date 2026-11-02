@echo off
rem Builds the VS Code extension for AmberScript (.ams) and installs it. Reload the VS Code window afterwards.
setlocal
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0..\tools\vscode-amberscript\build.ps1" -Install
exit /b %ERRORLEVEL%

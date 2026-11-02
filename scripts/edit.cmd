@echo off
rem Builds and starts the map editor (Windows; scripts/edit.sh on Linux). Without an argument the first map of content\maps is opened.
rem   edit.cmd               opens the first map (cellar)
rem   edit.cmd meadow        opens content\maps\meadow.tmx
rem   edit.cmd path\to\map.tmx
rem Extra arguments are passed on (for example --scale 1). Ctrl+S saves the TMX (the old file becomes .bak).
setlocal
if not defined CSHIFTC set "CSHIFTC=cshiftc"
pushd "%~dp0..\game" || exit /b 1
if not exist Amber.Player\lib\libglfw3.a powershell -NoProfile -ExecutionPolicy Bypass -File Amber.Player\get-glfw.ps1
"%CSHIFTC%" build Amber.Player
if errorlevel 1 (
	popd
	exit /b 1
)
Amber.Player\bin\amberplayer.exe --edit %*
set "CODE=%ERRORLEVEL%"
popd
exit /b %CODE%

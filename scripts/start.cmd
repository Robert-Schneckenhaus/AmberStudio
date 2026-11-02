@echo off
rem Builds amberplayer and plays the game in game/content (Windows; scripts/start.sh on Linux). Extra arguments are passed on, for example: start.cmd --scale 3
rem Other modes: start.cmd --check-content   start.cmd --headless --script tests\playthrough.txt
rem The compiler is cshiftc from the PATH, or the one CSHIFTC names. The first build fetches GLFW (get-glfw.ps1).
setlocal
if not defined CSHIFTC set "CSHIFTC=cshiftc"
pushd "%~dp0..\game" || exit /b 1
if not exist Amber.Player\lib\libglfw3.a powershell -NoProfile -ExecutionPolicy Bypass -File Amber.Player\get-glfw.ps1
"%CSHIFTC%" build Amber.Player
if errorlevel 1 (
	popd
	exit /b 1
)
Amber.Player\bin\amberplayer.exe %*
set "CODE=%ERRORLEVEL%"
popd
exit /b %CODE%

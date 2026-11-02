@echo off
rem Baut die C-Laufzeit und den Szenario-Laeufer (c\build\amber_trace.exe) mit clang oder gcc.
rem Der Compiler kommt aus der Umgebungsvariable AMBER_CC, sonst wird clang aus MSYS2 (C:\msys64\clang64\bin) benutzt.
setlocal
if "%AMBER_CC%"=="" set "AMBER_CC=C:\msys64\clang64\bin\clang.exe"
pushd "%~dp0" || exit /b 1
if not exist build mkdir build
"%AMBER_CC%" -std=c99 -Wall -Wextra -pedantic -Werror -Iinclude src\amber_pack.c src\amber_rt.c tools\amber_trace.c -o build\amber_trace.exe
set "CODE=%ERRORLEVEL%"
popd
if not "%CODE%"=="0" exit /b %CODE%
echo Gebaut: c\build\amber_trace.exe
exit /b 0

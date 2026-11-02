@echo off
rem Runs the tests of the repository (Windows; scripts/test.sh on Linux).
rem   test.cmd               everything: build, unit tests, content check, playthrough, pack, studio
rem   test.cmd unit          only the unit tests (tests\Amber.Tests: compiler, interpreter, pack, screens, C runtime)
rem   test.cmd content       only compile the tables and scripts of the example game (game\content)
rem   test.cmd playthrough   only the scripted run of the example game (headless, screenshots in game\out)
rem   test.cmd pack          the same run from a cooked pack file (--build-pack, --pack)
rem   test.cmd studio        only the scripted run of Amber Studio (on a copy of the content in game\out\studio)
rem The compiler is cshiftc from the PATH, or the one CSHIFTC names. The first build fetches GLFW (get-glfw.ps1).
rem The C runtime tests need a C compiler: AMBER_CC (for example the clang of the CShift toolchain) or clang/gcc on the PATH.
rem Amber Studio needs the trees, splitters, tabs and held keys of System.Ui (CShift after 0.41): with an older compiler
rem CSHIFT_STDLIB names the stdlib folder of a CShift checkout of master; without it the studio is skipped in "all".
rem The exit code is 0 if everything passed.
setlocal
set "ROOT=%~dp0.."
set "MODE=%~1"
if "%MODE%"=="" set "MODE=all"
if not defined CSHIFTC set "CSHIFTC=cshiftc"

if /i not "%MODE%"=="all" if /i not "%MODE%"=="unit" if /i not "%MODE%"=="content" if /i not "%MODE%"=="playthrough" if /i not "%MODE%"=="pack" if /i not "%MODE%"=="studio" (
	echo Unknown mode "%MODE%". Use: all, unit, content, playthrough, pack, studio.
	exit /b 2
)

pushd "%ROOT%" || exit /b 1
set "PLAYER=%CD%\game\Amber.Player\bin\amberplayer.exe"

echo == Build
if not exist game\Amber.Player\lib\libglfw3.a (
	powershell -NoProfile -ExecutionPolicy Bypass -File game\Amber.Player\get-glfw.ps1
	if errorlevel 1 goto :failed
)
"%CSHIFTC%" build src\Amber.Script.Cli
if errorlevel 1 goto :failed
"%CSHIFTC%" build src\Amber.Palette.Cli
if errorlevel 1 goto :failed
"%CSHIFTC%" build tests\Amber.Tests
if errorlevel 1 goto :failed
"%CSHIFTC%" build game\Amber.Player
if errorlevel 1 goto :failed
if not exist game\out mkdir game\out

if /i "%MODE%"=="all" goto :unit
if /i "%MODE%"=="unit" goto :unit
if /i "%MODE%"=="content" goto :content
if /i "%MODE%"=="pack" goto :pack
if /i "%MODE%"=="studio" goto :studio
goto :playthrough

:unit
echo == Unit tests
tests\Amber.Tests\bin\amber-tests.exe
if errorlevel 1 goto :failed
if /i "%MODE%"=="unit" goto :passed

:content
echo == Content (tables and scripts of the example game)
pushd game
"%PLAYER%" --check-content
set "CODE=%ERRORLEVEL%"
popd
if not "%CODE%"=="0" goto :failed
if /i "%MODE%"=="content" goto :passed

:playthrough
echo == Playthrough (game\tests\playthrough.txt)
if exist game\out\playthrough.amsv del game\out\playthrough.amsv
pushd game
"%PLAYER%" --headless --script tests\playthrough.txt --save out\playthrough.amsv > out\playthrough.log 2>&1
set "CODE=%ERRORLEVEL%"
popd
if not "%CODE%"=="0" (
	type game\out\playthrough.log
	goto :failed
)
echo Playthrough passed. Screenshots: game\out\ex_*.png, log: game\out\playthrough.log
if /i "%MODE%"=="playthrough" goto :passed

:pack
echo == Playthrough from a cooked pack (game\out\example.pack)
if exist game\out\pack_test.amsv del game\out\pack_test.amsv
pushd game
"%PLAYER%" --build-pack out\example.pack > out\pack_build.log 2>&1
set "CODE=%ERRORLEVEL%"
if "%CODE%"=="0" "%PLAYER%" --pack out\example.pack --headless --script tests\playthrough.txt --save out\pack_test.amsv > out\pack_run.log 2>&1
if "%CODE%"=="0" set "CODE=%ERRORLEVEL%"
popd
if not "%CODE%"=="0" (
	type game\out\pack_build.log
	type game\out\pack_run.log
	goto :failed
)
echo Pack run passed. Log: game\out\pack_run.log
if /i "%MODE%"=="pack" goto :passed

:studio
echo == Amber Studio (game\tests\studio.txt, on a copy of the content)
if defined CSHIFT_STDLIB (
	"%CSHIFTC%" build game\Amber.Studio --stdlib "%CSHIFT_STDLIB%" > game\out\studio_build.log 2>&1
) else (
	"%CSHIFTC%" build game\Amber.Studio > game\out\studio_build.log 2>&1
)
if errorlevel 1 (
	if /i "%MODE%"=="all" findstr /c:"TreeNode" /c:"TabBar" /c:"Splitter" /c:"Indent" /c:"Held" game\out\studio_build.log > nul && (
		echo Studio skipped: the compiler's System.Ui has no trees and tabs yet ^(set CSHIFT_STDLIB to ^<CShift^>\stdlib^).
		goto :passed
	)
	type game\out\studio_build.log
	goto :failed
)
if exist game\out\studio rmdir /s /q game\out\studio
mkdir game\out\studio\game
xcopy /e /i /q game\content game\out\studio\game\content > nul
pushd game
..\game\Amber.Studio\bin\amberstudio.exe --test tests\studio.txt --project out\studio > out\studio.log 2>&1
set "CODE=%ERRORLEVEL%"
popd
if not "%CODE%"=="0" (
	type game\out\studio.log
	goto :failed
)
echo Studio test passed. Screenshots: game\out\studio_*.png, log: game\out\studio.log

:passed
popd
echo == All requested tests passed.
exit /b 0

:failed
popd
echo == FAILED
exit /b 1

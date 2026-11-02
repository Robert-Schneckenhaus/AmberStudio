#!/bin/sh
# Runs the tests of the repository (Linux; scripts\test.cmd on Windows).
#   test.sh               everything: build, unit tests, content check, playthrough, pack, studio
#   test.sh unit          only the unit tests (tests/Amber.Tests: compiler, interpreter, pack, screens, C runtime)
#   test.sh content       only compile the tables and scripts of the example game (game/content)
#   test.sh playthrough   only the scripted run of the example game (headless, screenshots in game/out)
#   test.sh pack          the same run from a cooked pack file (--build-pack, --pack)
#   test.sh studio        only the scripted run of Amber Studio (on a copy of the content in game/out/studio)
# The compiler is cshiftc from PATH, or the one CSHIFTC names. The exit code is 0 if everything passed. Amber Studio needs
# the trees, splitters, tabs and held keys of System.Ui (CShift after 0.41): with an older compiler CSHIFT_STDLIB names
# the stdlib folder of a CShift checkout of master; without it the studio is skipped in "all".
ROOT=$(cd "$(dirname "$0")/.." && pwd)
MODE=${1:-all}
CSHIFTC=${CSHIFTC:-cshiftc}
PLAYER="$ROOT/game/Amber.Player/bin/amberplayer"

case "$MODE" in
	all|unit|content|playthrough|pack|studio) ;;
	*) echo "Unknown mode \"$MODE\". Use: all, unit, content, playthrough, pack, studio."; exit 2 ;;
esac

failed() {
	echo "== FAILED"
	exit 1
}

cd "$ROOT" || exit 1

echo "== Build"
"$CSHIFTC" build src/Amber.Script.Cli || failed
"$CSHIFTC" build src/Amber.Palette.Cli || failed
"$CSHIFTC" build tests/Amber.Tests || failed
"$CSHIFTC" build game/Amber.Player || failed
mkdir -p game/out

if [ "$MODE" = all ] || [ "$MODE" = unit ]; then
	echo "== Unit tests"
	tests/Amber.Tests/bin/amber-tests || failed
fi

if [ "$MODE" = all ] || [ "$MODE" = content ]; then
	echo "== Content (tables and scripts of the example game)"
	(cd game && "$PLAYER" --check-content) || failed
fi

if [ "$MODE" = all ] || [ "$MODE" = playthrough ]; then
	echo "== Playthrough (game/tests/playthrough.txt)"
	rm -f game/out/playthrough.amsv

	if ! (cd game && "$PLAYER" --headless --script tests/playthrough.txt --save out/playthrough.amsv > out/playthrough.log 2>&1); then
		cat game/out/playthrough.log
		failed
	fi

	echo "Playthrough passed. Screenshots: game/out/ex_*.png, log: game/out/playthrough.log"
fi

if [ "$MODE" = all ] || [ "$MODE" = pack ]; then
	echo "== Playthrough from a cooked pack (game/out/example.pack)"
	rm -f game/out/pack_test.amsv

	if ! (cd game && "$PLAYER" --build-pack out/example.pack > out/pack_build.log 2>&1 \
		&& "$PLAYER" --pack out/example.pack --headless --script tests/playthrough.txt --save out/pack_test.amsv > out/pack_run.log 2>&1); then
		cat game/out/pack_build.log game/out/pack_run.log 2> /dev/null
		failed
	fi

	echo "Pack run passed. Log: game/out/pack_run.log"
fi

if [ "$MODE" = all ] || [ "$MODE" = studio ]; then
	echo "== Amber Studio (game/tests/studio.txt, on a copy of the content)"

	if [ -n "$CSHIFT_STDLIB" ]; then
		"$CSHIFTC" build game/Amber.Studio --stdlib "$CSHIFT_STDLIB" > game/out/studio_build.log 2>&1
	else
		"$CSHIFTC" build game/Amber.Studio > game/out/studio_build.log 2>&1
	fi

	if [ $? -ne 0 ]; then
		if [ "$MODE" = all ] && grep -q "TreeNode\|TabBar\|Splitter\|Indent\|Held" game/out/studio_build.log; then
			echo "Studio skipped: the compiler's System.Ui has no trees and tabs yet (set CSHIFT_STDLIB to <CShift>/stdlib)."
		else
			cat game/out/studio_build.log
			failed
		fi
	else
		rm -rf game/out/studio
		mkdir -p game/out/studio/game
		cp -r game/content game/out/studio/game/content

		if ! (cd game && ../game/Amber.Studio/bin/amberstudio --test tests/studio.txt --project out/studio > out/studio.log 2>&1); then
			cat game/out/studio.log
			failed
		fi

		echo "Studio test passed. Screenshots: game/out/studio_*.png, log: game/out/studio.log"
	fi
fi

echo "== All requested tests passed."

#!/bin/sh
# Builds amberplayer and plays the game in game/content (Linux; scripts\start.cmd on Windows). Extra arguments are passed on, for example:
#   start.sh --scale 3
#   start.sh --check-content     start.sh --headless --script tests/playthrough.txt
# The compiler is cshiftc from PATH, or the one CSHIFTC names.
ROOT=$(cd "$(dirname "$0")/.." && pwd)
"${CSHIFTC:-cshiftc}" build "$ROOT/game/Amber.Player" || exit 1
cd "$ROOT/game" || exit 1
exec "$ROOT/game/Amber.Player/bin/amberplayer" "$@"

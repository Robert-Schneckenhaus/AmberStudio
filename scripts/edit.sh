#!/bin/sh
# Builds and starts the map editor (Linux; scripts\edit.cmd on Windows). Without an argument the first map of content/maps is opened.
#   edit.sh               opens the first map (cellar)
#   edit.sh meadow        opens content/maps/meadow.tmx
#   edit.sh path/to/map.tmx
# Extra arguments are passed on (for example --scale 1). Ctrl+S saves the TMX (the old file becomes .bak).
ROOT=$(cd "$(dirname "$0")/.." && pwd)
"${CSHIFTC:-cshiftc}" build "$ROOT/game/Amber.Player" || exit 1
cd "$ROOT/game" || exit 1
exec "$ROOT/game/Amber.Player/bin/amberplayer" --edit "$@"

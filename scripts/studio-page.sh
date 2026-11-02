#!/bin/sh
# Builds Amber Studio as one web page (wasm) with the example game (game/content) as the project, which the studio opens
# at the start (it looks for demo/game/content). Used by .github/workflows/pages.yml.
#
#   scripts/studio-page.sh <out.html>
#
# The compiler is cshiftc from PATH, or the one CSHIFTC names; CSHIFT_STDLIB names a stdlib folder with the trees, tabs
# and held keys of System.Ui (CShift after 0.41) if the compiler's own does not have them yet.
set -e
ROOT=$(cd "$(dirname "$0")/.." && pwd)
OUT=${1:?usage: studio-page.sh <out.html>}
CSHIFTC=${CSHIFTC:-cshiftc}
STUDIO="$ROOT/game/Amber.Studio"

rm -rf "$STUDIO/demo"
mkdir -p "$STUDIO/demo/game"
cp -r "$ROOT/game/content" "$STUDIO/demo/game/content"
rm -f "$STUDIO/demo/game/content/maps/edit_test.tmx" "$STUDIO/demo/game/content/maps/edit_test.tmx.bak"

# the project of the studio with the example as assets of the page
python3 - "$STUDIO/cshift.json" "$STUDIO/cshift.page.json" <<'PY'
import json, sys
project = json.load(open(sys.argv[1]))
project["assets"] = ["demo"]
json.dump(project, open(sys.argv[2], "w"), indent="\t")
PY

if [ -n "$CSHIFT_STDLIB" ]; then
	"$CSHIFTC" publish "$STUDIO/cshift.page.json" --stdlib "$CSHIFT_STDLIB" -o "$OUT"
else
	"$CSHIFTC" publish "$STUDIO/cshift.page.json" -o "$OUT"
fi

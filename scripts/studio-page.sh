#!/bin/sh
# Builds Amber Studio as one web page (wasm) with the example game (game/content) as the project, which the studio opens
# at the start (it looks for demo/game/content). Used by .github/workflows/pages.yml.
#
#   scripts/studio-page.sh <out.html> [content folder]
#
# A game that uses this repository (as a submodule, say) passes its own content folder; without one it is game/content.
# The compiler is cshiftc from PATH, or the one CSHIFTC names; CSHIFT_STDLIB names a stdlib folder with the trees, tabs
# and held keys of System.Ui (CShift after 0.41) if the compiler's own does not have them yet, and CSHIFT_WEB_JS the
# web/cshift.js of the same CShift checkout: it replaces the runtime that the compiler puts into the page (the one of its
# release, which does not report held keys yet). The page is changed so that the canvas fills the browser window with
# the pixels of the screen (the page of cshiftc publish shrinks a wide canvas to its column, which blurs the pixel font).
set -e
ROOT=$(cd "$(dirname "$0")/.." && pwd)
OUT=${1:?usage: studio-page.sh <out.html> [content folder]}
CONTENT=${2:-$ROOT/game/content}
CSHIFTC=${CSHIFTC:-cshiftc}
STUDIO="$ROOT/game/Amber.Studio"

rm -rf "$STUDIO/demo"
mkdir -p "$STUDIO/demo/game"
cp -r "$CONTENT" "$STUDIO/demo/game/content"
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

# the page: the canvas fills the window (and follows it), the runtime of CSHIFT_WEB_JS if given
python3 - "$OUT" "${CSHIFT_WEB_JS:-}" <<'PY'
import sys
path, runtime = sys.argv[1], sys.argv[2]
page = open(path, encoding="utf-8").read()

if runtime:
    start = page.index('<script type="module">') + len('<script type="module">')
    end = page.index("// ---- the page:")
    code = open(runtime, encoding="utf-8").read().replace("</script", "<\\/script")
    page = page[:start] + "\n" + code + "\n\n" + page[end:]

style = """
    html, body { margin: 0; padding: 0; height: 100%; overflow: hidden; background: #f2f2f2; }
    header { display: none; }
    canvas, canvas.shown { max-width: none; border-radius: 0; display: block; }
    #output { position: fixed; left: 0; right: 0; bottom: 0; max-height: 30vh; margin: 0; width: auto; }
    #output:empty { display: none; }
"""
page = page.replace("</style>", style + "</style>", 1)

fit = """
    // the canvas has the size of the window in pixels of the screen, so that the Ui draws them one to one
    const fitCanvas = () => {
        const ratio = globalThis.devicePixelRatio || 1;
        const width = Math.floor(globalThis.innerWidth), height = Math.floor(globalThis.innerHeight);
        canvas.style.width = width + "px";
        canvas.style.height = height + "px";
        canvas.width = Math.round(width * ratio);
        canvas.height = Math.round(height * ratio);
        // input wakes the program, which then draws a frame of the new size
        canvas.dispatchEvent(new PointerEvent("pointermove", { clientX: -1, clientY: -1 }));
    };
    globalThis.addEventListener("resize", () => { if (canvas.classList.contains("shown")) fitCanvas(); });
"""
marker = "    const files = {};"
assert marker in page, "unknown page of cshiftc publish"
page = page.replace(marker, fit + marker, 1)
options = "canvas, files, onOutput: print,"
assert options in page, "unknown page of cshiftc publish"
page = page.replace(options, options + ' args: ["--browser"],', 1)
hook = "onWindow: (width, height, title) => {"
assert hook in page, "unknown page of cshiftc publish"
page = page.replace(hook, hook + "\n                fitCanvas();", 1)
open(path, "w", encoding="utf-8").write(page)
PY

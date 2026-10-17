= Responsive reader development

The independent reader modules are in `tools/flow-reader`. They generate HTML
from the saved Typst entrypoint, using a temporary package overlay. The installed
packages, paged service, and source documents are not rewritten by a reader build.

== Build and inspect

```sh
python3 tools/flow-reader/build.py \
  --root /absolute/project \
  --entry main.typ \
  --package-path /absolute/typst/packages \
  --font-path fonts \
  --compiler /absolute/path/to/typst \
  --output dist/reader
```

The output directory contains `document.html`, `compile.log`, and `report.json`.
The command exits unsuccessfully when the content gate fails, even if Typst
successfully generates HTML. Review unsupported annotations, compiler warnings,
missing links, duplicate anchors, and unresolved annotation targets.

The package forks retain their original licenses. `packages/provenance.json`
records the original package versions and per-file hashes. Reader-specific
changes are target-aware and preserve paged output. The current CeTZ adapter
keeps an entire canvas together as an SVG; figure font and width policies still
need explicit validation before promotion.

== Local reader service

```sh
python3 tools/flow-reader/serve.py \
  --root /absolute/project \
  --package-path /absolute/typst/packages \
  --font-path fonts \
  --output dist/reader \
  --original-url https://original-paged-preview.example/ \
  --watch
```

The server binds loopback and reports its selected port. `--port` selects a
specific development port. `--allow-incomplete` permits a development preview
with visible fidelity diagnostics; do not use that flag for the mobile default.
`/api/state` exposes compile state and the accepted revision. `/health` indicates
whether a document is available, independently of whether the latest source
compiled successfully. A failed compile retains the previous document.

The reader supports native text selection, a heading outline, font size changes,
local equation scrolling, linked annotation dialogs, and reading anchors. Updates
wait for an active selection or annotation dialog to close. Persistent highlights,
source selection sharing, offline reload, and the remaining mobile rollout work
are tracked in the responsive-reader OpenSpec change.

== Sections and graphical annotations

The service publishes a revision-specific `/api/manifest` and HTML sections at
`/api/sections/section-N?revision=...`. Only the current section is inserted into
the browser DOM. The manifest resolves references and footnotes across sections.
Reading keys are assigned before partitioning, using named labels or contextual
text, so a section boundary change does not itself invalidate a saved passage.
Large vector drawings and embedded images are delivered unchanged as separate,
lazy-loaded assets. SVG drawings with interactive links remain inline.

Graphical annotations retain their original CeTZ programs. Opening a relationship
dialog measures the actual marked terms in its equation layout and sends those
rectangles to `/api/graphics`. The service evaluates the original program against
the measured geometry and returns a namespaced SVG overlay. No source code is
accepted in this request. The published revision and source fingerprint must
still match; source changes reject a new rendering until a current document is
available. Completed geometry requests are cached.

The initial implementation recompiles the full source for an uncached graphical
request. On the PDE project this can take several seconds; the dialog shows a
pending state. Reusing a persistent compiler is a subsequent performance task.
Drawing a connection correctly does not imply an arbitrary figure can be
recomposed automatically. Figure label sizes and narrow layouts still require
their own validation.

== Managed installation

The Reader lifecycle module belongs to this repository and reads the installed
Flow app's `--profiles` output on each start. Its configuration stores a parent
profile ID and Reader runtime/port options; it does not copy the project root,
fonts, entrypoint, or package settings. It installs its own LaunchAgent and does
not replace or restart the existing paged app or engine.

Install only from a clean commit:

```sh
python3 tools/flow-reader/install.py \
  --profile existing-flow-profile \
  --port 23627 \
  --public-url https://your-host.ts.net:23627/ \
  --start
```

During validation, add `--development` to retain the development notice and keep
the Reader out of the default mobile entry. The installer archives the committed
Reader sources into an immutable release under the Flow application support
directory. A stable launcher in `reader/bin/flow-reader` exposes `--profiles`,
`--launch-plan ID`, `--status ID`, and `--control start|stop|restart ID`. Reader IDs
append `-reader` to the parent ID. Port validation includes every saved Flow
profile, including projects that are currently stopped.

Tail Hosting registers the derived profile using this launcher as `managerBinary`
and `kind: typst-reader`. The maintained adapter is
`apps/macos/tail-hosting-reader.patch`. It delegates lifecycle operations and reads
`/api/state` for compile status; an HTTP 200 from the shell does not imply a valid
compile. The new Tailscale Serve route must use a free port and preserve all
existing handlers. The installer itself does not modify ingress.

To stop or roll back, stop the Reader ID with its launcher, disable only its new
ingress port, and retain the original paged endpoint. Installed Reader releases
are kept for recovery. Changing a saved Flow project's paths takes effect when
its Reader is restarted.

== Verification

```sh
FLOW_READER_PACKAGES=/absolute/typst/packages \
  python3 -m unittest discover -s tools/flow-reader/tests -v
node --check tools/flow-reader/web/reader.js
```

The integration tests invoke the compiler and compare paged outputs. Browser
checks must additionally inspect MathML namespaces: HTML footnote markers inside
math need token integration points, otherwise browsers may render the remaining
equation as ordinary text despite a successful compilation.

Before mobile rollout, verify the complete actual document at 320, 390, 430, and
768 CSS pixels, large font sizes, reference navigation, annotations, saved edits,
and recovery after compilation errors. Preserve and separately verify the
original paged endpoint. Compilation success alone is not a release gate.

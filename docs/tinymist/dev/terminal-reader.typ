= HTML Reader beside Neovim

`tools/flow-reader/terminal.mjs` runs the existing HTML Reader in headless
Chromium and sends its rendered image to a native terminal pane. Mouse and
keyboard input reach the real browser document, including its text selection,
mathematics, figures, reading settings, Save for Codex and review marks.
`editors/neovim/lua/tinymist/reader.lua` optionally opens that pane beside Neovim
and connects saved-source navigation and verified source highlights.

This integration opens the Flow HTML Reader. It does not replace or configure
`typst-preview.nvim`, and it does not change the installed paged preview service.

== Requirements and terminal choice

Use Node.js 20 or newer, Python 3, a Typst compiler with HTML support, Playwright, and an
installed Google Chrome. An explicit Chromium executable can replace Chrome.
The Neovim integration also requires a recent Neovim with `vim.fs`, `vim.json`,
and local RPC support.

iTerm2 on macOS is the default automatic pane launcher. The renderer selects
Kitty PNG graphics when `TERM_PROGRAM` is `iTerm.app`; this requires an iTerm2
version with Kitty graphics support and was tested with iTerm2 3.7.4. Kitty
graphics output is also available in compatible native terminals with
`--protocol kitty`; other pane launchers require an explicit Neovim `open`
argument array. The legacy `--protocol iterm2` override uses OSC file display,
which may request confirmation for every frame. The renderer does not change
the terminal's confirmation or security preferences.

PowerShell is a shell, and iTerm2 is the terminal that displays the images.
Neovim may run inside a PowerShell session in iTerm2. The iTerm2 launcher starts
the renderer through `/bin/sh` with a literal executable argument list, so the
default profile's shell does not need to parse the renderer command.

Run the Reader in a native terminal pane. Neither Neovim `:terminal` nor tmux is
supported for this image transport. Windows Terminal is not a supported default
host; this renderer does not implement its SIXEL image transport. A custom
`open` launcher must create a native pane in a terminal that
actually implements the selected image protocol; choosing `--protocol` cannot
add graphics support to an incompatible terminal.

== Browser dependency and diagnosis

Playwright is optional for the rest of this repository. Install it in a separate
directory if it is not already available. The following example changes only
that external directory, without changing repository dependencies or lockfiles:

```sh
npm install --prefix /absolute/path/flow-reader-browser playwright
```

The renderer uses the installed Chrome channel, so a separate Playwright browser
download is unnecessary for that setup. Select the module explicitly, either
with `--playwright-module`, the Neovim `playwright_module` option, or the shared
environment variable. In a POSIX shell:

```sh
export FLOW_READER_PLAYWRIGHT_MODULE="/absolute/path/flow-reader-browser/node_modules/playwright/index.mjs"
```

In PowerShell:

```powershell
$env:FLOW_READER_PLAYWRIGHT_MODULE = "/absolute/path/flow-reader-browser/node_modules/playwright/index.mjs"
```

From the checkout, diagnose dependencies and the current terminal:

```sh
node tools/flow-reader/terminal.mjs --check
```

The JSON report includes the browser version, image protocol, terminal status,
and tmux or embedded-Neovim detection. Dependency success alone does not prove
that a terminal displays images. `ready: false` reports an unsupported current
host. To use a Chromium executable other than installed Chrome, add
`--browser-executable /absolute/path/to/chromium`; in Lua use
`browser_executable` with the same absolute path.

== Standalone Reader

Replace every `/absolute/path` value with an existing path. Start an independent
Reader for a saved project in a native graphics terminal pane:

```sh
node /absolute/path/tinymist-engine-mobile/tools/flow-reader/terminal.mjs \
  --root /absolute/path/project \
  --entry main.typ \
  --package-path /absolute/path/typst/packages \
  --compiler /absolute/path/to/typst \
  --output /absolute/path/flow-reader-state/html \
  --profile /absolute/path/flow-reader-state/chromium \
  --port 23628
```

These continuation characters are POSIX shell syntax. In PowerShell, put the
same arguments on one line or use PowerShell's own continuation syntax.
`--font-path` can be repeated for additional font directories. If
`--package-path` is omitted, the bundled Reader package overlay is used; point
it at the project's package directory when other local packages are needed.
`--root` starts and owns a watched Python Reader service. Exiting this renderer
also stops that service.

To display an already running Flow Reader, supply its stable URL instead of
`--root`:

```sh
node /absolute/path/tinymist-engine-mobile/tools/flow-reader/terminal.mjs \
  --url http://127.0.0.1:23628/ \
  --profile /absolute/path/flow-reader-state/chromium
```

An existing service remains running when the renderer exits. Reader URLs are
HTTP or HTTPS URLs. A generic website or the paged preview URL does not supply
the Flow Reader APIs required by this host.

`--snapshot /absolute/path/check.png` captures a real Reader image without a
terminal. This is useful for checking document delivery and browser rendering;
it does not validate a physical terminal's image display or mouse handling.
`--cell-width` and `--cell-height` override automatic terminal cell-size queries
when a terminal reports incorrect dimensions. iTerm2's cell report supplies
logical points, which map to browser CSS pixels even on a Retina display. Its
whole-window pixel report is ignored because it includes other native panes.

== Opt-in Neovim setup

Place the following configuration in your own Neovim setup, replacing the
absolute paths. This example starts a separate Reader for `main.typ`, uses a
dedicated browser profile, and opens a right-hand native iTerm2 pane when a
Typst buffer is opened. No user configuration file is edited automatically.

```lua
vim.opt.rtp:prepend(
  "/absolute/path/tinymist-engine-mobile/editors/neovim"
)
require("tinymist.reader").setup({
  root = "/absolute/path/project",
  entry = "main.typ",
  command = {
    "/absolute/path/to/node",
    "/absolute/path/tinymist-engine-mobile/tools/flow-reader/terminal.mjs",
  },
  compiler = "/absolute/path/to/typst",
  package_path = "/absolute/path/typst/packages",
  playwright_module =
    "/absolute/path/flow-reader-browser/node_modules/playwright/index.mjs",
  profile = "/absolute/path/flow-reader-state/chromium",
  output = "/absolute/path/flow-reader-state/html",
  port = 23628,
  auto_open = true,
})
```

Set `auto_open = false` for manual startup. `:FlowReader start` opens the pane,
`:FlowReader sync` requests a saved-source cursor update, and `:FlowReader stop`
stops only the renderer and service owned by this editor session. Quitting
Neovim also stops them. After quitting the Reader with `q`, a later
`:FlowReader start` can open it again.

For a different compatible terminal, `open` must be a nonempty array containing
the native pane launcher's executable and its fixed arguments. The integration
appends the renderer's executable and arguments as separate array entries.
Configure that launcher's command boundary according to its own interface;
the integration does not provide a shell-command-string opener.

The optional `url` Lua setting connects an existing Reader instead of starting
a new one. That Reader must have been started with `--editor-server` equal to
this Neovim instance's `v:servername`, and it must use the matching Neovim
executable when needed. The host rejects a mismatched connection before source
highlights are enabled. The ordinary project setup above supplies the RPC
address and executable automatically.

== Reading controls

Drag with the mouse to select actual HTML text. Use the visible Reader toolbar,
Tab and Enter, or these shortcuts while focus is outside a text input:

#table(
  columns: (auto, 1fr),
  inset: 6pt,
  table.header([Key], [Action]),
  [`h`], [Apply a compiler-verified highlight to source and save it.],
  [`s`], [Add a local red review strike to the selection.],
  [`u`], [Undo the latest review strike.],
  [`X`], [Clear all local review strikes for this document.],
  [`g`], [Move Neovim to the selected supported source passage.],
  [`j` / `k`], [Scroll down or up.],
  [`q`], [Quit this Reader host.],
)

The normal Reader settings and Save for Codex remain browser controls, reachable
with Tab and Enter. Save for Codex uses the same acknowledged HTTP action and
private service record as the web Reader, with exact logical text and supported
source context. It does not send a message or start a Codex turn. Shortcuts pass
through while typing in an input. Review strikes stay in browser storage; source
highlighting is an explicit file change. Source navigation requires Neovim.

For a terminal-owned service, read context with its explicit local URL:

```sh
python3 tools/flow-reader/focus.py --url http://127.0.0.1:24002/
```

The service defaults to `OUTPUT/focus.json` and checks live identity, revision,
source inputs/hash/excerpt and age before returning usable context. A fresh
unmapped selection retains its text without inventing a source location. A
managed service also supports `manage.py --focus ID`. See the responsive Reader
guide for the portable Tail Hosting adapter and exact-source freshness fields.
Legacy browser quotation records remain untouched and are not sent or migrated;
the quotation library and its paint/relocation UI are removed.

== Saved-source synchronization and conflicts

Cursor polling and Save for Codex share the accepted HTML block-to-source map.
It includes literal content inside wrappers and closure bodies, formatted prose
and complete mathematics where compilation verifies the same block identity and
canonical text. Selected subpassages retain exact UTF-8 source positions; whole
equations resolve to their complete original expression. Ordered selections
across blocks can resolve when they remain in one source file. Context saving
and navigation read accepted mappings without starting another compilation.

This remains a conservative map. Partial formulas, unsupported generated text,
cross-file selections and ambiguous repeated output can be unavailable for code
navigation. Changed saved inputs invalidate the map. The Reader still renders
that content and retains its ordinary
selection and local review actions. Source highlights use the existing separate
compiler-verification path and can also decline uncertain selections.

Editor-to-Reader navigation skips a modified current buffer. Reverse navigation
and source highlighting refuse an unsaved target buffer or a changed saved
snapshot. The original buffer and file are preserved. Save the document
explicitly, wait for the Reader's accepted refresh, and retry. A successful
verified highlight is applied and saved through Neovim, keeping its loaded
buffer consistent with the file. Navigation also defers while a Reader
selection, dialog or recent reading gesture is active.

== Persistent marks and lifecycle

Keep both the browser profile and the Reader origin stable to preserve review
strikes, reading position and appearance. An origin includes
the scheme, hostname and port: changing `127.0.0.1` to `localhost`, or changing
the port, selects a different browser-storage origin even with the same profile.

Without explicit values, standalone project mode derives a stable port and
profile from its project identity. The Neovim integration stores its profile and
HTML output under its own state directory unless configured otherwise. A busy
owned-service port produces an error; startup does not silently choose another
origin. Use different profiles for independent simultaneous browser instances.
These terminal profiles do not share the installed app's browser state.

Normal quit, editor stop and handled termination signals restore raw input, mouse reporting and
the previous terminal screen. The renderer closes its browser and any Reader
service it started. A service supplied through `--url` remains independently
owned.

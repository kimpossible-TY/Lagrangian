= HTML Reader beside Neovim

`tools/flow-reader/terminal.mjs` runs the existing HTML Reader in headless
Chromium and sends its rendered image to a graphics terminal. Mouse and
keyboard input reach the real browser document, including its text selection,
mathematics, figures, reading settings, Save for Codex and review marks.
`editors/neovim/lua/tinymist/reader.lua` opens a right-hand view inside Neovim
by default and connects saved-source navigation and verified source highlights.
Source and Reader share the same terminal connection.

This integration opens the Flow HTML Reader. It does not replace or configure
`typst-preview.nvim`, and it does not change the installed paged preview service.

== Requirements and terminal choice

Use Node.js 20 or newer, Python 3, a Typst compiler with HTML support, Playwright, and an
installed Google Chrome. An explicit Chromium executable can replace Chrome.
The default internal view requires Neovim 0.12 or newer on the host, with its
built-in TUI directly attached to the graphics terminal. Explicit native/manual
modes retain the older `vim.fs`, `vim.json` and local RPC prerequisites.

PowerShell can remain your shell. For a remote Mac, the compiler, Python, Node,
Playwright, Chrome and Neovim run on the Mac; Windows Terminal displays the
images and sends input over the terminal connection.

Windows Terminal versions with SIXEL support use `--protocol sixel`. SIXEL was
introduced in the #link("https://devblogs.microsoft.com/commandline/windows-terminal-preview-1-22-release/")[1.22 release series].
The renderer detects `WT_SESSION` or `TERM_PROGRAM=Windows_Terminal` locally;
remote connections can omit those values. The internal Neovim view queries the
terminal directly; standalone native hosts can select the protocol explicitly.
SIXEL derives its palette from each browser screenshot, with up to 216 colors
and 40 grayscale levels for text. The shared HTML theme still owns highlight
colors; the terminal conversion keeps dominant colors close to the screenshot.
Its default capture rate is 2 frames per second; `--fps 1` reduces traffic on
slower links.
Image output, scrolling and selections still use the same real HTML document.

With explicit `open = "native"`, iTerm2 on macOS is the automatic native pane launcher. The renderer selects
Kitty PNG graphics when `TERM_PROGRAM` is `iTerm.app`; this requires an iTerm2
version with Kitty graphics support and was tested with iTerm2 3.7.4. Kitty
graphics output is also available in compatible native terminals with
`--protocol kitty`; other pane launchers require an explicit Neovim `open`
argument array. The legacy `--protocol iterm2` override uses OSC file display,
which may request confirmation for every frame. The renderer does not change
the terminal's confirmation or security preferences.

Neovim may also run inside a PowerShell session in iTerm2. The iTerm2 launcher starts
the renderer through `/bin/sh` with a literal executable argument list, so the
default profile's shell does not need to parse the renderer command.

The internal view sends images through Neovim's `nvim_ui_send`; its terminal
buffer handles input only. Running the standalone CLI inside an ordinary
Neovim `:terminal` is still unsupported. Use a direct terminal connection outside
tmux/screen. A custom `open` launcher must create a native pane in a terminal
that implements the selected image protocol.

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

In a Windows Terminal remote pane, run diagnosis with `--check --protocol sixel`.
An explicit protocol is a user choice; diagnosis does not probe the terminal's
SIXEL implementation or guarantee that an intervening transport preserves image
control sequences.

== Windows Terminal connected to a remote Mac

Load the opt-in module below, connect to the Mac as usual, and run
`:FlowReader start`. Neovim keeps source on the left and opens the interactive
Reader on the right. No second connection, Windows pane command or browser port
forwarding is required. All runtime dependencies remain on the Mac.

While the browser and first image are being prepared, the Reader window's
Neovim statusline shows `Loading...` with a rotating indicator and elapsed
seconds. The normal Reader controls replace it when the first current image
arrives. You can return to source with `Ctrl-W h` while waiting, or close the
view with `:FlowReader stop`.

When lualine is already loaded, Reader focus pauses its statusline and shows the
Reader's loading feedback or controls. Returning to source or another window/tab
restores lualine immediately; closing the Reader also restores it. Tabline,
winbar, your statusline layout and lualine configuration are preserved. The
integration does not load lualine if you do not use it.

Other statusline plugins can retain their display between Reader message
changes. Refreshing only the statusline does not repaint the document image.

The default `open = "split"` queries the attached terminal through Neovim's
`TermResponse` events, including when SSH omits Windows Terminal environment
markers or reports placeholder pixel sizes. The recognized Windows Terminal
device-attribute feature set selects its default SIXEL grid of 10 by 20 virtual
pixels per cell, independent of physical font pixels. The view uses that grid
for browser and mouse coordinates, selects cursor-relative SIXEL placement and
preserves the editor cursor around each image. Other SIXEL profiles with unknown
geometry receive an error before a Reader window is opened.

Kitty graphics uses the logical cell dimensions from `ReportCellSize` when
available. Otherwise it uses a logical viewport of 9 by 18 pixels per cell;
Kitty scales the image to its explicit row/column placement. Browser input uses
the same logical coordinates.

Capability queries tolerate additional/reordered Windows features and retry
once if a remote reply is lost or delayed, within a four-second budget.
A confirmed Windows grid is retained for that attached TUI across Reader
restart and resize; a new UI must establish its own capabilities. Kitty logical
cell dimensions are refreshed after terminal resize. Failure messages include
the received DA1, Kitty and cell reports, or `none` when no matching reply was
received. Neovim continues to own terminal input throughout; startup sends no
process stop/resume signals and does not open or read the TTY independently.
This preserves interactive shell job control on the remote Mac. Timeout,
cancellation and query errors remove the temporary response handler and leave
the editor available.

If an older version leaves a `suspended` shell message, run `fg` in that same
remote shell to return to the existing editor. Save your work and reopen Neovim
with the updated module before using `:FlowReader start` again.

Click the Reader or move into its window to read. `Ctrl-W h` returns to source;
`Ctrl-W l` returns to the Reader when it is on the right. The usual
`Ctrl-\` followed by `Ctrl-N` leaves terminal input mode for Neovim commands.
`:FlowReader stop` or closing the Reader window stops its owned host and service.
Pressing `q` in the Reader also closes it when focus is outside an HTML text input.
A later `:FlowReader start` opens a fresh view with the same persistent profile.
Source cursor polling continues to use the source window while the Reader is
focused; a verified reverse jump focuses source and retains the Reader window.

With Neovim mouse support enabled, drag the vertical divider between source and
Reader left or right to resize both windows. Divider and source gestures remain
with Neovim when the pointer enters the Reader; a selection started inside the
Reader stays with the browser through release, even outside its window.
While the Reader has focus, `Ctrl-W <` narrows it, `Ctrl-W >` widens it, and
`Ctrl-W =` equalizes the windows. These controls keep Reader input mode active
and are also available when mouse support is disabled. The integration preserves
your global mouse setting and uses Neovim's existing split sizing.

Resizes invalidate pending frames. Hidden tabs, overlapping floating windows and
Neovim command-line entry hide the image until the view is available again.
Cleanup redraws the editor; it does not replace modified source buffers. Mouse
precision is limited to character cells, and Neovim can coalesce mouse coordinates
received in one input batch. Physical Windows Terminal and Devtunnel forwarding
remain separate checks from the automated POSIX TUI/browser fixtures.

For a separate native pane, set `open = "native"` for iTerm2 or supply a native
launcher argument array. For another remote connection, explicitly use
`:FlowReader prepare` or `open = "manual"`. Read the printed command with
`:messages`, reconnect in another native terminal, and append `--protocol sixel`:

```sh
node /path/to/terminal.mjs --session /path/from/neovim --protocol sixel
```

That private session retains the editor's RPC, persistent profile and lifetime.
The command uses Neovim's configured shell quoting; PowerShell invokes quoted
executables with `&`. Repeating start in manual mode repeats its command.
Stopping the editor or Reader invalidates its manifest and stops an attached
host. Only one host may attach to each prepared session.

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

Set `auto_open = false` for command-only startup. `:FlowReader start` opens the
internal view by default,
`:FlowReader sync` requests a saved-source cursor update, and `:FlowReader stop`
stops only the renderer and service owned by this editor session. Quitting
Neovim also stops them. After quitting the Reader with `q`, a later
`:FlowReader start` can open it again.

For automatic opening in a different compatible terminal, `open` must be a nonempty array containing
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

The internal view restores the editor display and releases its input/window hooks
on quit, stop and editor exit. Native hosts also restore raw input, mouse reporting
and the previous terminal screen after normal quit or handled termination signals. The renderer closes its browser and any Reader
service it started. A service supplied through `--url` remains independently
owned.

#set page(paper: "a4", margin: 22mm)
#set text(size: 10pt)
= Shared Flow preview in VS Code

Use the running tinymist-flow service to read the same saved document on a phone
and in VS Code. With Code Tunnel, the extension runs on the Mac hosting Flow;
Windows displays the reader. Install an engine and extension containing these
options before enabling them.

== Configure

Start the document in tinymist-flow, then set these workspace options:

```json
{
  "tinymist.preview.sharedFlow": true,
  "tinymist.compileOnSave": true
}
```

Run the normal Tinymist document preview command. The extension matches the open
file to the most specific Flow project root and opens a *Saved Flow Preview*.
A nested project takes precedence. Multiple profiles with the same root are
ambiguous and must be resolved before opening the reader. The managed entrypoint,
fonts, packages and theme settings belong to the Flow profile.

Remote connections, including Code Tunnel, use VS Code port forwarding so the
client does not need access to the phone's private HTTPS address. Local sessions
use the profile's HTTPS address when available, otherwise port forwarding.
The reader header includes an *Open in Browser* button using the same address. The extension reads profiles on the host from
`~/Library/Application Support/tinymist-flow/profiles.json`, or `FLOW_DATA_DIR`
when that host environment variable is set. Untrusted workspaces cannot use this
integration. A stopped service produces an error; start it in Flow and retry.

== Editing and diagnostics

Save an edit to update the shared reader. Unsaved buffers stay in the language
server and are not sent to the Flow service. Reopening the preview reuses the
existing reader panel. Closing it disconnects that viewer without stopping Flow.
Click text in the embedded reader or a reader opened with *Open in Browser*
to reveal its saved source file and
cursor position. This reuses Flow's source mapping without starting another
compiler. Save an unsaved target source before navigating from the saved preview.
The normal phone URL retains Codex location recording without moving the desktop
cursor. VS Code-opened browser URLs carry a temporary connection to that editor
window. After reloading VS Code, reopen the browser reader from VS Code to renew
that connection. Source files must belong to the matched project.
Editor-to-preview synchronization, slide previews and browsing/development
previews require sharedFlow to be disabled.

`compileOnSave` changes automatic full-document compilation after typing. Source
snapshots update immediately, so language queries can still inspect current text.
A save, buffer close, real external file update or explicit compile/entry change
releases deferred work. An already running evaluation finishes safely and its
superseded result cannot be published. Full compilation diagnostics update on
those triggers. Queries can still evaluate expressions and consume memory.

== Performance boundaries

Phone and VS Code viewers of the same profile and theme share the existing Flow
preview compiler. Different themes can require separate compiled outputs.
Opening this reader starts no additional LSP preview server. LSP compilation for
saved diagnostics is still independent: this integration does not share every
Typst or comemo object across processes. Disabling compileOnSave restores the
previous automatic typing behavior; disabling sharedFlow restores ordinary
Tinymist preview routing.

Compare automatic compile counts during a fixed edit burst, saved-result latency,
process memory and stale-result rejection before and after enabling the options.
A small test fixture verifies work reduction but cannot predict the improvement
for a large book or a particular tunnel connection.

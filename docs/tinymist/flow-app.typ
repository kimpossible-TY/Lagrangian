#set page(paper: "a4", margin: 22mm) if sys.inputs.at("x-target", default: "pdf") != "md"
#set text(size: 10pt)
#if sys.inputs.at("x-target", default: "pdf") != "md" [
  #align(center)[
    #image("../../assets/branding/lagrangian.png", width: 25mm, alt: "Lagrangian app icon")
  ]
]

#let doc-ref(target-label, target-fragment, body) = {
  if sys.inputs.at("x-target", default: "pdf") == "md" {
    link("#" + target-fragment, body)
  } else {
    link(target-label, body)
  }
}

= Lagrangian user guide

#set heading(numbering: "1.")

Read and review live Typst documents on your Mac, phone, or tablet. This guide covers everyday reading actions, document setup, installation, and recovery.

= Home window <home-window>

The home window keeps one always-visible row for each job: add or configure the project, start reading, and control the preview service.

== Top bar and hero

The top bar carries two icon buttons on the right: *+* (프로젝트 추가) adds a project, and *⚙* (프로젝트 설정) opens the project settings sheet. The center hero shows only the brand mark (`NativeBrandMark`) and the title *Lagrangian*; it carries no supporting text.

== Project card

The center card selects the project and starts reading.

- Project picker: choose which project this window controls.
- Shortcut path: the entry file's location is shortened to `.../<dir>/<entry.typ>`.
- Action row: the primary button *Read* (읽기 시작), the secondary button *Offline document* (오프라인 문서), and the *•••* overflow menu (*주소 복사*, *설정 파일 보기*, *프로젝트 추가…*, *Connect Editor…*, *Disconnect Editor*, *사용·업데이트·복구 안내*).

Reading and offline actions stay in this row; project settings are not edited on the home window.

== Preview service card

One line below the project card reports the service and keeps its actions in the same row.

- Stopped: a status dot, *프리뷰 서비스 · 중지됨*, the address `127.0.0.1:<port>`, and *Start* (시작) and *Logs* (로그).
- Running: a status dot, *프리뷰 서비스 · 실행 중*, the address `127.0.0.1:<port>` as a clickable link, and *External Reader* (외부 Reader), *Stop* (중지), and *•••* (*재시작*, *로그 열기*).

The dot follows the service state; reader-side activity is described in *Understand preview status* below.

== Bottom bar

The bottom bar keeps two persistent items: the *로그인 시 앱 열기* checkbox on the left and the *프로젝트 설정…* link on the right. The link opens the same settings sheet as *⚙*.

== Project settings sheet

Settings are not edited on the home window. *⚙* or *프로젝트 설정…* opens a separate sheet with:

- *프로젝트 이름* (`name`)
- *프로젝트 폴더* (`root`) with *찾아보기…* (`browseRoot`)
- *진입 파일* (`entry`) (text field, no separate Browse button)
- *글꼴 폴더 (`;` 구분)* (`fonts`)
- *로컬 패키지 폴더* (`packages`)
- *로컬 포트* (`port`)
- *HTTPS 주소 (선택)* (`publicURL`)

*설정 저장* (Save settings) is available inside this sheet only; cancelling or closing the sheet without saving discards unsaved field edits.

= Open your first preview

Use Flow to manage a document's live preview while editing its Typst source in your usual editor. You need an installed Flow app and a `.typ` entry file. For installation, see #doc-ref(<first-installation>, "first-installation")[First installation] below. For version identification and guide matching, see #doc-ref(<identifying-installed-versions-and-guides>, "identifying-installed-versions-and-guides")[Identifying installed versions and guides] below.

+ Open `~/Applications/Lagrangian.app` (received via Finder or installed package). The Flow menu appears in the menu bar.
+ In the home window, click *+* (프로젝트 추가) in the top bar and select the document's `.typ` entry file. The #link("examples/reading-demo.typ")[reading demo] is a small document for trying selection, highlights, references, and themes.
+ Set *프로젝트 폴더* (`root`) to the workspace root if the entry file uses sibling files or folders outside its own directory (using *찾아보기…*), and confirm *진입 파일* (`entry`).
+ Adjust *글꼴 폴더 (`;` 구분)* (`fonts`), *로컬 패키지 폴더* (`packages`), *로컬 포트* (`port`), or *HTTPS 주소 (선택)* (`publicURL`) if needed, then click *설정 저장* (Save settings) inside the settings sheet.
+ Click *Read* (읽기 시작) in the project card. In an installed app supporting native reading, Flow saves changed settings, starts or reuses the managed document service, and prepares the native Reader window. Save a source edit in your editor to refresh that document. Use the separate *External Reader* action when you explicitly want the web reader.

*Result in an installed native app:* Flow opens a native Reader for the project. Settings validation, the request, document acceptance and actual native presentation remain distinct progress states. The separately selected External Reader opens its configured browser address. Historical web-only installed releases used Start reading to open that browser directly; check the guide and metadata bundled with the app as described in #doc-ref(<identifying-installed-versions-and-guides>, "identifying-installed-versions-and-guides")[Identifying installed versions and guides]. If preparation fails, the explanation stays in the window; correct the cause and choose *Read again* (다시 읽기). *Logs* (로그) provides further details. Each project keeps its own entry file, settings, port, and preview lifecycle.

== Project controls and settings

The project card's picker selects which project the home window controls. *Stop* (중지) disables its service until you use Start again; *Restart* (다시 시작) restarts it. Closing the home window or quitting the menu bar app leaves started previews running.

*Read* (읽기 시작) also works for an already running project and waits for its available document before native preparation. *External Reader* (외부 Reader) is the explicit web action; the existing phone/tablet web URL remains available. Service start/stop/restart controls manage the service separately from Read. Switching projects or stopping cancels the current pending Read. Service and settings operations run in the background so the window remains responsive.

Project settings are edited only in the settings sheet described in *Home window* above: *프로젝트 이름*, *프로젝트 폴더* (with *찾아보기…*), *진입 파일*, *글꼴 폴더 (`;` 구분)*, *로컬 패키지 폴더*, *로컬 포트*, and *HTTPS 주소 (선택)*. *설정 저장* (Save settings) is not offered on the home window itself, and cancelling or closing the sheet without saving discards unsaved edits.

Font paths are relative to the project root and separated by semicolons. For example, `fonts;../shared-fonts` selects two folders. The local package folder is optional; use it when your document depends on local packages. Saving changed settings restarts a running preview.

The *로그인 시 앱 열기* checkbox at the bottom of the home window opens the menu bar app after login. Started preview services also resume after login independently of that checkbox. Sleeping or logging out can interrupt availability.

== Resume after an interruption

After a temporary network interruption or engine restart, keep the reading tab open. The paged and HTML readers retain the accepted document and retry the connection. Returning to the tab or reconnecting the network prompts a fresh check. Reading position and zoom stay with the document; an active text selection keeps its displayed content until you explicitly clear it. Source actions still check that the selected revision and source are current.

Flow pauses background status checks while the Mac sleeps and checks again after wake or a network change. Recovery does not open an extra tab or start a project you stopped. On battery, in Low Power Mode or under elevated thermal conditions, Flow checks idle services less often; an explicit reading action remains immediate. Flow respects system sleep and keeps requested previews running independently of the app. Remote reading is available again once the Mac is awake and its network route has recovered.

The app's *Usage, update and recovery guide* (사용·업데이트·복구 안내) menu opens the bundled PDF. This web guide and that PDF are generated from the same Typst source.

= Read on a phone or tablet

Use remote reading when the preview runs on your Mac and you want to read on another device. The Mac must be awake, the project preview must be running, and the viewing device must have access to the configured Tailscale tailnet and HTTPS route. Tail Hosting supplies that route and its access policy.

+ In Tail Hosting, configure a Tailscale HTTPS route to the project's local backend, `127.0.0.1:<local-port>`. Match the port shown in Flow's project settings.
+ In Flow, enter that route's HTTPS address in *HTTPS address* (HTTPS 주소), then click *Save settings* (설정 저장). Saving restarts a running preview with the allowed origin.
+ Click *Start* if needed, then *Copy address* (주소 복사).
+ On the phone or tablet, connect to the tailnet as required by its access policy and open the copied HTTPS URL in a browser.
+ Confirm that the document renders and that a saved source edit on the Mac appears on the device.

*Result:* The device reads the same live project through its configured HTTPS address. Flow binds the backend to loopback; `http://127.0.0.1:<port>/` refers to the device itself when opened on a phone and cannot reach the Mac. Entering an HTTPS address in Flow does not create a Tailscale route. When you change the local port, update the Tail Hosting route too.

The HTML Reader shows a small notice below the toolbar while saved changes compile,
load and appear on screen, including when you have scrolled down. It disappears
after the accepted content is displayed. If text selection pauses an update,
*Clear selection and update* (선택 해제 후 갱신) releases it explicitly. Open notes,
the outline and reading gestures also delay updates until they end. Connection,
compilation and loading errors remain visible while the previous document stays
readable; mathematics and figures retain their own local composition feedback.

== HTML Reader offline reading and device computation

For a configured HTML Reader, open its Reader HTTPS address. In Reader settings, wait
until the offline status confirms that the document is available offline. You may add
the page to the phone's Home Screen using the browser's share menu. Reopening without
the server restores the last complete saved document; an online connection is required
to download newer source changes. Browser storage can be removed by the device, in
which case reconnect to download the document again.

Supported mathematical decorations and native figure labels adapt to reading width
and font size on the viewing device. Reading settings provide a two-position
*Device computation load* (이 기기 계산 부하) slider. New viewers start at *Low*:
document compilation stays on the server and local math and figure layout remain active.
*High* offers the browser's local compiler as a temporary worker while its page is
visible and connected, if the server provides a browser compiler. Swipe, tap or use
the keyboard to choose a level. Explicit saved choices survive reloads; previous on/off
choices become High/Low. Selecting Low, closing or hiding the page releases its work;
the server validates and
adopts results for every viewer. Large documents can use substantial memory and battery,
so enable this only on a device suitable for the document.

When using Highlight offline, the Reader first stores an explicit request on the
device. It has not yet saved the source. After reconnecting, the server checks the
original revision and source before saving; changed or uncertain requests require
checking the latest document and selecting again. Reader settings show pending and
review-needed counts. Repeated delivery of the same request cannot repeat its source
edit, and an older result cannot dismiss a newer selection.

= Select and copy text

Select text to copy a passage or use the reading actions. On a touch device, long-press text and adjust the native selection handles; use the device's Copy action for ordinary copying. In the paged web preview, the toolbar near the bottom offers Copy, Highlight, Save for Codex, and Red strike. HTML and terminal readers instead use Ask to open a composer; only explicit Send starts inference. Native Reader selection, source copying, and conversation actions follow the dedicated native component flow described in #doc-ref(<native-reading-controls-and-source-component>, "native-reading-controls-and-source-component")[Native reading controls and source component] below.

If a selection starts or ends inside a formula, it expands to the complete expression after the selection settles. Formula numbering, attached labels and nearby prose stay outside that expression. *Copy* (복사) writes complete formulas as Typst source including `$...$`, keeps surrounding prose as displayed, and separates copied blocks with one newline. If a formula has no verified source, Copy uses the displayed text and reports that the Typst source could not be confirmed. (In the native Reader, ordinary body or Original PDF copy copies displayed text, while verified Typst source copying is a separate permission and pathway.)

#image("images/mobile-selection.png", width: 65mm, alt: "Reading demo with a selected sentence and the Highlight, Save for Codex, and Red strike actions")

*Result:* The selection stays on the rendered revision while you use it. Preview updates wait during an active text selection on desktop and touch devices; dismiss the selection to apply pending edits. On a touch device, wait for the formula selection handles to settle before copying so the whole expression is included.

In the paged web preview, dragging or long-pressing does not save a Codex source location. Use *Save for Codex* to save the exact selected text, or dismiss the selection and briefly tap a passage to save a source location. Scrolling alone does not update the saved context.

= Highlight in source

Use a highlight when you want a passage marked in the Typst document itself, including later exports.

+ Select a passage in the preview.
+ Choose *Highlight* (하이라이트) in the bottom toolbar.
+ Wait for the saved-source acknowledgement and compilation. Check the marked passage in the updated preview.

*Result:* This edits the original `.typ` source. The normal source watcher recompiles it, and the highlight appears in exports. To remove a source highlight, edit the source in your editor; the browser's mark-undo action applies to red strikes.

*Conditions:* Flow must map the full selection to a supported source range, and the candidate document must compile before it is saved. Plain literal text can use the built-in `highlight` function. Complete equations require the source module's callable `highlighted` helper; see *Document setup* below. Whole inline references can be included with supported text or equation selections. Partial equations or references, reused content, other code or markup, selections spanning source files, and changed source snapshots cannot be edited automatically. If the action is rejected, the selection stays available so you can use Save for Codex in the paged web preview instead; in HTML or terminal, use Ask and then explicitly Send only when ready.

= Save text for Codex (paged web preview)

Use this paged-preview action to preserve a passage and its location before asking Codex to explain, review, or edit it.

+ Select the text you want to discuss.
+ Choose *Save for Codex* (Codex 저장) and wait for confirmation that the selected text was saved.
+ In a Codex session with a configured local selection reader, ask a question such as: “Explain the passage I saved from the preview.” Specify the project when you have several previews.

*Result:* Flow saves up to 8000 selected characters and the selection's page endpoints alongside its source context. This saves context; it does not send a message, start a Codex turn, or compile the document. A newer compiler revision requires selecting again. A brief tap saves a location instead of an exact text selection.

Saved context has no time limit. The local reader still checks the service,
document version and source before using its location. For a project registered
with both paged and HTML readers, the integrated Tail Hosting reader finds the
latest saved text within that same entry document and identifies its reader;
a newer tap-only location in another reader does not hide the saved text.

== Connect a local selection reader

Flow writes selection records on the Mac running the preview. Codex needs a local skill or tool that reads the correct project's record and checks it against the current service and source. Flow does not install that reader automatically. List profile details, including each `focusFile`, with:

```sh
~/Applications/Lagrangian.app/Contents/MacOS/Lagrangian --profiles
```

Configure your reader for the selected project's `focusFile`, stored under `~/Library/Application Support/Lagrangian/focus/<profile-id>.json`. It should identify the project, check the saved selection's status and source against the current document, and request a fresh selection if the context is stale. After a service restart, tap or select the passage again before asking about it.

If your project is registered with the existing Tail Hosting focus reader, a local Codex tool or skill can invoke it with the project root:

```sh
/path/to/Tail_hosting/bin/tail-hosting focus --project /absolute/project
```

Replace the paths with your installation and project. This reader is supplied by Tail Hosting and requires its registered profile integration; it is not a command included in the Flow bundle. A Codex session on another computer needs access to this Mac's record and source before it can use the saved selection. Without a reader, copy the selected passage into your question.

= Add browser review marks

Use a red strike for a reading or review note that should stay outside the source document.

+ Select text and choose *Red strike* (빨간 취소선).
+ Use *Undo* (되돌리기) to remove the latest mark, or *Clear marks* (표시 지우기) to remove this document's temporary marks in this browser.

*Result:* A red line appears across the selected fragments without source edits or compilation. Marks are stored separately by document in this browser and survive refresh, theme changes, and scrolling through unchanged pages. They are excluded from PDF exports and do not synchronize to other devices.

*Conditions:* A page whose text or layout changes loses its old marks to avoid displaying them over the wrong passage. When browser storage is unavailable, such as in some private sessions, marks stay in memory only and disappear when the view closes.

= Choose a document theme

Use the theme selector to match the reading device or choose a palette for this viewer.

+ Choose *System* (기기 설정) to follow the device's light or dark appearance, including later changes.
+ Choose *Light* (라이트) or *Dark* (다크) to override that behavior for this viewer. Choose System again to resume device following.

*Result:* Supported documents render with their native light or dark colors. Each viewer chooses independently on the same project port and HTTPS URL. Switching preserves scroll and preview zoom; it waits while a touch text selection is active. The `t` shortcut toggles the native palette.

*Conditions:* The document must read the `theme` input with `"light"` and `"dark"` values; see *Document setup* below. Documents without that contract still preview normally but do not change their native palette. The reading demo supports both themes.

= Return from a reference

Use this when you follow an internal equation, figure, or heading reference and want to resume the passage you were reading.

+ Click or tap the reference.
+ Choose *Back to reference* (참조 위치로 돌아가기) to return to the position immediately before following that link.

*Result:* The preview restores the previous page position, including after preview zoom or window resizing, and the button disappears. Following another reference replaces the return destination with the position before that latest link. This return is for the current document view and clears when the view is replaced, including a theme switch or refresh. It can appear alongside Jump to change.

= Resume the latest visual edit

Use change navigation to return to work after reopening a preview or to inspect a new edit while reading elsewhere.

+ Save an edit that changes rendered output and let the preview render it.
+ Open or refresh the preview to return to its latest successfully rendered visual edit.
+ If a recent reading gesture defers navigation, choose *Jump to change* (변경 위치로) when ready.

*Result:* The project remembers a rendered edit location. Theme switches and reconnecting an already rendered viewer preserve the current reading position. This tracks visual edits, rather than a history of where you scrolled; comments and other edits with no rendered change do not move the saved position.

*Conditions:* While the preview service runs, saves made with all viewers closed retain their latest source location without compiling an idle palette. Light and dark share that source location and map it into their own layouts when opened, including a palette that has not been used before. A current saved location takes priority. If none is usable, Flow can use Git changes against HEAD that map to the document; these are cumulative changes, rather than the order of edits. Without a usable saved, tracked-source, or Git location, the initial view stays at the beginning.

= Understand preview status

The small status ring shows activity while the browser prepares the renderer, connects, waits for the document, compiles, or draws pages. It disappears after rendering. Compiler or rendering failures show a static error; a dropped connection shows reconnection activity. These states describe activity rather than estimated completion percentages.

*Returning from another app:* iOS and iPadOS can suspend a home-screen web app and interrupt its connection. Returning checks the existing connection and reuses it if it responds. A dropped connection retries on return, keeping the document, zoom and reading position visible. A native text selection holds the replacement document until the selection is dismissed. Source updates still render normally. Background suspension or a page reload can still require document transfer; connection recovery does not guarantee continuous background access.

- *Update paused while text is selected:* updates wait until you dismiss the selection; waiting longer does not resume them. Tap *Clear selection and update* in the status notice, or dismiss the selection by tapping an empty area of the document. This paused state has no loading ring, and your selection remains available until you clear it.
- *Long wait or compilation error:* open Logs in Flow and check the document in your editor. A responding HTTP server does not prove successful compilation.
- *Mobile URL does not connect:* confirm that the Mac is awake, the preview is started, the device has tailnet access, and the route points to the current local port. Check the HTTPS address saved in Flow.
- *Theme colors do not change:* confirm the document's theme input contract below.
- *Highlight is rejected or a saved selection is stale:* wait for rendering and select again. In a paged web preview, unsupported source ranges can be saved with Save for Codex instead. In HTML/terminal, Ask opens the composer and only explicit Send submits it.
- *macOS requests document access:* complete the native consent prompt on the Mac. Preview activity itself is not proof that a permission prompt is open.

= Document setup

These settings belong to the Typst document. The #link("examples/reading-demo.typ")[reading demo] provides a complete working example.

== Native theme colors

Read the theme input and use it for your page and text colors:

```typ
#let dark = sys.inputs.at("theme", default: "light") == "dark"
#set page(fill: if dark { rgb("172033") } else { white })
#set text(fill: if dark { white } else { black })
```

Managed previews keep independent light and dark variants and compile each while viewers are connected. Viewers of the same palette share a compilation; each viewer downloads only its selected variant. Color-only variants preserve layout most predictably. When both palettes have viewers, compiling both uses additional host memory and CPU. PDE and Ewald already follow this theme contract.

For standalone paged preview, opt in with:

```sh
tinymist preview main.typ --follow-system-theme
```

This overrides an explicit `--input theme=...` while retaining unrelated inputs. Without the flag, preview keeps its existing behavior. HTML and bundle outputs do not support this option.

== Theme-aware source highlighting

Define a callable `highlighted` helper in the module that contains the selected source:

```typ
#let highlighted(body) = highlight(
  fill: if dark { rgb("63521f") } else { rgb("fff0a8") },
  body,
)
```

Flow uses this helper to write `#highlighted[...]` for supported text and complete equations, preserving the document's theme handling. Without it, literal text uses `#highlight[...]`; equations cannot be highlighted automatically. Rendered glyph coverage verifies complete equations even when their notation differs from source, and an isolated compiler render verifies complete selected inline references, including a scoped `ref` helper's generated equation number.

A custom helper must accept a single text element or equation as well as mixed content. When iterating its body, use `if body.has("children") { body.children } else { (body,) }` so singleton content does not cause a missing-field error.

== Saved change locations

Each profile stores one private `changes/<profile-id>.json` record in Application Support, independently of explicit assistant selections, with separate light and dark positions. Unchanged source retains its position across service restarts and renderer updates. If source changed while the service was stopped, the first compilation establishes a baseline without guessing a new edit from the first changed page.

The Git fallback considers staged, unstaged, and nonignored new source files used by this document. With multiple candidates it chooses the earliest body page, then the topmost position on that page. It does not infer editing order. Standalone paged preview can opt in by setting `TINYMIST_PREVIEW_CHANGE_FILE` to an absolute path; records are scoped to the project root and entry file. This does not expose a new network endpoint.

= Files and ownership

- App and installed engine: `~/Applications/Lagrangian.app`
- Profiles and explicit selection records: `~/Library/Application Support/Lagrangian/`
- Logs: `~/Library/Logs/Lagrangian/`
- Previous app bundles: Application Support's `releases/` folder
- LaunchAgents: `~/Library/LaunchAgents/`

Flow manages engine execution, project profiles and preview lifecycle. Tail Hosting owns Tailscale HTTPS routes and remote access policy. Changing a local port requires updating its Tail Hosting route. Original Typst source files stay in their project folders.

= First installation <first-installation>

On macOS 13 or newer, native app packaging uses Git, the Swift compiler,
Python 3 and a verified prebuilt engine. Fetch a single successful run while
checked out at its exact head H. Engine build source E can be older on a cache
hit; current app, reader and delivery must all bind H.

```sh
run=123456789
engine=$(python3 scripts/flow-app.py fetch-engine --run-id "$run")
reader=$(python3 scripts/fetch-reader-bundle.py --run-id "$run")
FLOW_SIGN_IDENTITY=<existing-certificate-sha1> python3 scripts/flow-app.py build --engine "$engine"
python3 scripts/verify-native-reader-app.py dist/Lagrangian.app --require-delivery
```

The existing build call automatically consumes the engine-local same-run
context, reauthenticates the exact R/H archive and reader, verifies current source
and payload, and compiles fresh Swift/resources. An older cached app is never
relabelled as current. Missing payload or identity, tamper and stale/mixed bindings
fail before installation and preserve a valid previous stage. This source change
does not replace the installed updater or prove actual deployment.

The artifact name stays `flow-engine-darwin-arm64`; its transport is a bounded,
source/checksum/run-bound tar plus JSON envelope, preserving executable modes,
internal relative links and hidden signed payload. A damaged or missing archive
is rejected without flat, installed-app or scratch fallback. Raw archive digest
and the fetched external engine's authenticated chmod are separate bindings.
The same-run cache is reauthenticated before build. Old engine source E may be
reused; current app and tar are produced anew for H on both cache paths.

For a standalone or installed engine, select its path explicitly and supply a
current verified delivery matching the clean checkout and engine input:

```sh
python3 scripts/flow-app.py build --engine /absolute/path/to/flow-engine \
  --delivery /absolute/path/to/current-verified-delivery --identity <existing-certificate-sha1>
python3 scripts/verify-native-reader-app.py dist/Lagrangian.app --require-delivery
```

See #link("dev/native-reader-delivery.typ")[portable input preparation and signing].
An installed engine binary alone supplies neither the same-run context nor the
current portable payload; a bare `build` does not supply those missing inputs.
An explicit ad-hoc `--identity -` is available for isolated checks; it does not
establish certificate continuity. `--management-only` is a nonshipping fixture
whose app fails require-delivery verification. There is no implicit dependency
acquisition, installed-app payload fallback or ad-hoc identity fallback.
Native engine compilation remains a separate pipeline operation under the
#link("dev/development.typ")[remote Rust build policy]. Packaging does not compile Rust.

Managed previews compile the light and dark variants when viewers connect to them. Source updates are retained while a variant has no viewers; reconnecting requests its current document. Multiple viewers of the same palette share one compilation. The host classifies interactive CPU work and cache maintenance separately for macOS scheduling.

The app keeps the upstream engine protocol and VS Code configuration names. For the installed engine, set `tinymist.serverPath` to the absolute path ending in `Lagrangian.app/Contents/MacOS/flow-engine`. Remote VS Code settings must refer to the remote host's installed path.

= Signing and macOS consent

The app bundle ID is `io.github.kimpossible-ty.lagrangian`. Builds choose `--identity`, then `FLOW_SIGN_IDENTITY`, then a saved signing identity. Without a selected identity, or when the selected certificate is unavailable, native delivery fails closed instead of signing ad hoc. Isolated checks can explicitly select `--identity -`; this does not establish certificate continuity. Because macOS treats the renamed app as a new identity, it may request Documents access again; approve that request in macOS when prompted. The app name and icon identify the request, but do not replace OS consent. Administrator authentication must be completed by the user when macOS requires it.

For repeated personal builds, create one code-signing certificate using Keychain Access's Certificate Assistant or use an existing Apple signing identity. Retain the certificate and its private key in Keychain, then save its identity once:

```sh
python3 scripts/flow-app.py configure-signing --identity "Lagrangian Local Signing"
run=123456789
engine=$(python3 scripts/flow-app.py fetch-engine --run-id "$run")
reader=$(python3 scripts/fetch-reader-bundle.py --run-id "$run")
python3 scripts/flow-app.py build --engine "$engine" --version 0.1.9
python3 scripts/verify-native-reader-app.py dist/Lagrangian.app --require-delivery
```

This versioned build uses the saved identity and verified same-run context from
a clean checkout at H, as in First installation. A standalone engine instead
requires the explicit current verified `--delivery` shown there.

The first signing probe may ask for Keychain access. Complete authentication locally and select Always Allow for `/usr/bin/codesign` to reuse this key. Configuration is saved only after the probe succeeds; cancelling leaves the previous configuration intact.

The saved configuration is `~/Library/Application Support/Lagrangian/signing.json`; it contains the public certificate identifier, not a private key or password. The first Lagrangian launch migrates the former `tinymist-flow` support and log directories and leaves symlinks at the old locations for existing services. Builds choose `--identity`, then `FLOW_SIGN_IDENTITY`, then the saved identity. A missing configured identity stops the build instead of falling back to ad-hoc signing. Both the app and bundled engine use the same certificate; the release manifest records its SHA-256 fingerprint, which bundle verification checks for both signatures. A personal self-signed certificate establishes a local identity; it does not provide Apple notarization or public distribution approval.

The initial switch from ad-hoc signing may require one new Documents approval. Keep the same certificate for later builds. Verify document delivery after a subsequent installed build before treating permission continuity as confirmed. Certificate replacement or loss may require consent again.

= Update and recover

When moving from `tinymist-flow.app`, install `Lagrangian.app` alongside it. The installer does not delete the former app or stop its services. On first launch, Lagrangian moves the old Application Support and Logs directories to the new names and leaves compatibility symlinks so existing services can continue using their recorded paths. Do not remove the old app until you have opened Lagrangian, verified your profiles and previews, and disabled or updated its legacy login item. To transfer a running preview to Lagrangian, use its Restart control; this preserves the existing profile and LaunchAgent label while updating the executable path. macOS may request document access again because the bundle identifier changed.

The former bundle remains available at `~/Applications/tinymist-flow.app` until you remove it yourself. After the first Lagrangian installation, subsequent updates use the recovery-aware replacement flow below:

```sh
run=123456789
engine=$(python3 scripts/flow-app.py fetch-engine --run-id "$run")
reader=$(python3 scripts/fetch-reader-bundle.py --run-id "$run")
python3 scripts/flow-app.py build --engine "$engine" --identity <existing-certificate-sha1>
python3 scripts/verify-native-reader-app.py dist/Lagrangian.app --require-delivery
python3 scripts/flow-app.py install dist/Lagrangian.app
```

Use one run R whose head H matches the clean checkout. Build reauthenticates that run's engine-local context, portable payload and reader before compiling current Swift/resources. A standalone or installed engine instead needs an explicit `--engine` path and matching current verified `--delivery`, as shown in First installation. Engine and preview changes follow the separate #link("dev/development.typ")[remote Rust build policy]; packaging then uses a compatible verified prebuilt engine and current delivery. For a confirmed release, use a short feature branch, run the relevant tests, merge into `main`, and build from a clean commit with an explicit `--version`.

The installer checks the bundle signature, engine hash and version before replacing anything, waits for managed profiles to stop, backs up the prior Lagrangian app, restarts those profiles, and checks HTTP startup. If startup fails, it restores the previous Lagrangian bundle. Verify document rendering after installation; HTTP alone does not establish document health.

An ad-hoc update can wait for macOS Documents consent before opening its HTTP listener. To allow time for that prompt, defer live health verification during the single installation:

```sh
python3 scripts/flow-app.py install dist/Lagrangian.app --defer-health-check
```

This option retains the new bundle while consent is pending. Bundle validation, backups, and recovery from replacement or service-control errors still apply. After completing consent, verify the running profile, its HTTP endpoint, and delivery of the rendered document. The installer reports that this live verification remains pending.

```sh
python3 scripts/flow-app.py verify ~/Applications/Lagrangian.app
python3 scripts/flow-app.py rollback
```

Rollback restores the previous app while preserving profiles and source files. Keep the backup until the new version is confirmed. Release metadata records the Flow source revision, dirty-worktree flag, engine version and input hash, bundled engine hash, app version and signing mode. Tag confirmed installed releases as `flow-vX.Y.Z`; retain one code commit per feature and a separate deployment record.

= Tail Hosting migration

```sh
python3 scripts/flow-app.py migrate-tail-hosting --dry-run /path/to/Tail_hosting
python3 scripts/flow-app.py migrate-tail-hosting /path/to/Tail_hosting
```

This imports `typst-always-preview` profiles and migrates `typst-reader` services after `Lagrangian --migrate-data` has moved reader data. It verifies SHA-256 hashes of `reader/{engines,releases}` in place, checks reader backend ports for conflicts, and updates `reader/config.json` and `reader/bin/flow-reader` through `tools/flow-reader/install.py`. A running reader keeps its legacy launchd label, and that installer refuses to replace a release while the job is running. Migrate checks that the plist serves this reader and that its launcher path resolves to the installed `flow-reader`, stops the job with `launchctl bootout`, waits until it is unloaded, installs the new release, then starts it again with `flow-reader --control restart`. If that restart fails, migrate prints the command and the reader's current state. A failed install bootstraps the previous plist again. It updates an existing background login LaunchAgent to `Lagrangian.app`, backs up the prior registry, launcher, configs and plists, and installs lifecycle adapters when they are not already present. `--dry-run` checks the same preflight, including a clean Reader checkout, that each reader is stopped or will be stopped, and that the service id is the parent profile id plus `-reader`, then prints the plan. Restore puts the previous preview services, reader plists, and `tinymist-flow.app` background manager back. It restarts a reader that was running with `launchctl bootout`, a wait until the job is unloaded, then `enable` and `bootstrap` of the restored plist, because that release matches its launcher path exactly. Inspect macOS consent and verify HTTPS document delivery before considering migration complete.

```sh
python3 scripts/flow-app.py restore-tail-hosting --dry-run
python3 scripts/flow-app.py restore-tail-hosting
```

The restore command reinstates the old registry, launcher, preview and reader LaunchAgents, reader configuration, and `tinymist-flow.app` background manager from the migration backup. Unrelated hosted services are preserved. The adapter does not create or change Tailscale Serve routes.

= Identifying installed versions and guides <identifying-installed-versions-and-guides>

Use the information inside the exact app bundle you intend to run. A source checkout identifies its Git revision. A packaged app also has a bundle and executable identity.

1. In Finder, select the app bundle and choose *Show Package Contents*. Read `Contents/Resources/release.json`.
2. `version` identifies the app release. `sourceRevision` identifies the build checkout commit and `sourceDirty` records whether it included local changes. `engineVersion`, `engineSHA256` and `engineInputSHA256` identify the engine independently. `managementOnly` identifies management-only delivery. Builds with a verified native payload can also record `nativeDeliveryCapabilities`. Older manifests may omit those fields.
3. In normal mode, choose *사용·업데이트·복구 안내* in Flow's menu to open that app's `Contents/Resources/UserGuide.pdf`. The local fixture disables this external-opening action; read `Contents/Resources/UserGuide.pdf` from the same supplied app bundle instead. Use the guide shipped with the app you are checking.
4. For a packaged development candidate, compare the bundle and executable hashes with its supplied inspection record and use its designated isolated profile. A source-only candidate has no packaged executable to inspect. Build metadata identifies the inputs and capabilities. Feature acceptance requires the separate results for that build.


= Maintaining the Flow app

Use this repository for the app, engine, preview frontend, branding, packaging, tests, and documentation. Keep app work in `apps/macos`, branding in `assets/branding`, and behavior contracts in OpenSpec. Package a compatible external engine or build the maintained engine sources. Both paths supply mobile selection, assistant focus, device themes, change restoration, selected text actions, and preview activity status. Small local fixes can stay lightweight. Preserve upstream copyright, Apache License 2.0, and applicable third-party notices.

Test a replacement engine for compatibility before bundling it, and keep its version and hash alongside the Lagrangian source revision. App work does not require rebuilding or maintaining the language server. The private production repository is `kimpossible-TY/Lagrangian`. Engine and preview implementations are maintained in this tree; Tinymist crate, CLI and protocol identifiers remain unchanged.

= Isolated native Reader inspection <managed-native-inspection>

Managed-service native app inspection uses a Lagrangian-owned temporary project
and a local fake inference provider. This procedure has an explicit service owner;
see #doc-ref(<local-native-fixture-inspection>, "isolated-native-fixture-inspection")[local fixture inspection] for the service-free path. The production document, source and conversation
APIs retain their existing guards. An explicit dev root isolates data, logs,
home and service paths; dev-only no-activate avoids forced foreground activation.
Reader body Copy and verified Source copy use a private named pasteboard in this
isolated composition, while ordinary app use retains the system clipboard.

See #link("dev/native-reader-app-verification.typ")[the isolated inspection procedure]
for setup, bounded foreground serve, exact app arguments, clipboard inspection
and owned cleanup. Preparing that fixture does not launch the app, install or
restart a service, verify original PDF delivery, or establish GUI/VoiceOver and
complete native application acceptance. Use only the approved final staged app
for the later independent inspection.

The historical 09c staged candidate integrated core, page and published inputs.
Its partial GUI results belong to that build. For a new packaged inspection,
match the candidate's build metadata and isolated profile as described in
#doc-ref(<identifying-installed-versions-and-guides>, "identifying-installed-versions-and-guides")[Identifying installed versions and guides].
For the historical frozen NA13 inspection use
`tests/flow-app/native-reader-app/test_page_delivery_bundle.py gui-fixture` and
`test-output/delivery-production/NA13/final-app-v1/inspection-commands.json`.
Its `gui-inspection-001` is setup-only/running=false; follow the recorded
serve/status/appCommand/stop commands without rerunning setup there. A new
inspection requires a new root and exact pinned compiler/package inputs.
NA14 source requires its own final integration, GUI/AX and review evidence;
prior GUI evidence cannot be relabelled for its new executable bytes.


= Native Reader window

The native Reader uses one toolbar row per mode. Navigation stays on the left, the mode or page controls in the center, and search and overflow on the right.

== Body toolbar

*본문* shows the reflowed native body and *원본 PDF* opens the original pages. The single body row carries:

- Left: the brand mark (`NativeBrandMark`) and the *목차 ▾* dropdown.
- Center: the *본문 | 원본 PDF* segmented control.
- Right: search (*⌘F*), *Aa* (view settings popover), and the *•••* overflow menu (새로고침, 검토 표시/실행 취소/지우기, 오프라인 저장, 저장 문서 열기, 저장 목록 새로고침, PDF 내보내기, 계정 관리, 돌아가기, 확대/축소/페이지 맞춤 등).

*목차* navigates the body. If an active body or PDF selection holds the view, dismiss the selection before choosing the other mode. Selecting a PDF search result creates a display selection. Typing a search query alone does not hold the view. *새로고침* is disabled for a restored offline copy. When restoration is in progress or fails, the recovery status takes precedence and the existing recovery controls handle retry or cancel.

== View settings

*Aa* opens a popover that applies each change to the body immediately; there is no separate preview, apply or cancel step. Escape closes the popover and keeps the current values.

- Theme (테마): *밝게 | 어둡게 | 자동*.
- Text size (글자 크기): *−*, the current size in points, and *+*.

The bottom of the popover also offers *오프라인 저장* and *PDF 내보내기*.

== Native reading controls and source component <native-reading-controls-and-source-component>

A valid text selection in *본문* shows a compact capsule beside the selection with *Copy* (복사), *Ask* (질문하기) and *View source* (원문 보기). The capsule is absent while nothing is selected, and Escape closes it while leaving the selection in place. The selection holds background replacement.

=== Select, copy, and ask

1. Select text in *본문*. The active selection holds background replacement and
   shows the capsule. The Reader can place the capsule beside the selection or
   dock it on a separate row when the text fills that area.
   Escape closes the capsule and leaves the selection in place.
2. Choose *질문하기* in the capsule. For a live
   selection of at most 32 blocks, this opens the local question composer.
   Opening or editing a new question there does not fetch its account, models
   or conversation, save a server draft or start inference. Selection-related
   eligibility checks may run independently.
3. Enter the question and click *Send* when ready to submit. For a new composer,
   the first *Send* checks the current selection, account, permissions and
   available models before opening the conversation. If no model was selected,
   it may use the first available model and continue the same explicit *Send*.
   If you change the question or model during preparation, review the current
   draft and click *Send* again. A stale selection or unavailable permission
   prevents submission. *Save for Codex* belongs to the paged web preview.

Within the same living Reader context and exact selected range, Ask can reopen
an already created conversation and restore its latest local draft and selected
model, including an unconfirmed Send's original UUID, question and model.
Switching between known passages keeps their drafts separate within the bounded
presentation cache. Known ranges in the same paragraph reuse that conversation's
latest accepted snapshot, draft and pending identity. A new selection ticket is checked again by the existing
owner when you explicitly Send. This does not promise immediate recovery of a
first draft before its conversation exists, or recovery across an app restart.
Recovery never sends. A newer edit stays visible when history confirms an older
message.
Changing or clearing the selection blocks a new Send; Stop and Refresh conversation
retain the existing conversation/context authorization. Stop response is available
only when the accepted conversation is streaming; local account/open preparation alone provides no Stop target.
While a Stop is in flight, its button and repeated callbacks cannot start another
Stop or discard the first completion.
For an unconfirmed Send, first choose *Refresh conversation* successfully.
If the valid same-conversation history confirms the original user message, you
may explicitly Send a new question. If it does not confirm that message, retry
only the original question and model; the app reuses its original message UUID.
A failed Refresh keeps the uncertainty and pending message in place. Reopening
the composer or editing its draft is not a retry. If Refresh did not confirm the
pending message and you close and reopen the composer, refresh that conversation
again before retrying. Refresh is available for an open conversation when no other
conversation action is running; it retains conversation/context authorization
when the selection changes.

*복사* copies display text in both *본문* and *원본 PDF*, including a full display
selection longer than the limit for source and chat actions. To copy verified
Typst source, use *원문 보기* on a live eligible body selection. The app checks the
current document and source before copying. *원문 강조* also requires source write
permission. *편집기 위치로* requires a current, explicitly connected editor.

In *원본 PDF* or a restored or offline read-only copy, you can read and copy
display text. Live source, editor and question actions are unavailable there.
Pending retirement of an editor connection on an otherwise live body does
not block ordinary reading or Ask. A new editor action still needs its own
current authorization.

== Offline PDF

*원본 PDF* opens the original pages with one toolbar row, including a restored offline copy.

- Left: the brand mark (`NativeBrandMark`), *목차 ▾*, and the *오프라인 PDF* badge.
- Center: grouped page navigation: `<`, the current page and the total page count (`current / total`), and `>`.
- Right: the search field and the *•••* overflow menu.

A search hit or a selection in live/online *원본 PDF* shows a compact capsule with *Copy* (복사) and *Close* (닫기) above the caption *원본 PDF · 복사·검색만 지원*, while in an offline restored copy it shows *오프라인 PDF · 복사·검색만 지원*.

== Reader shortcuts

- *⌥⌘T*: 더보기(•••) 메뉴 토글
- *⌘F*: search in *본문*, or focus the original-PDF search field
- *Esc*: close the popover, the capsule, or search
- Arrow keys: move between pages and navigate the body

= Historical source component: home feedback

The v5 source component separates *Service start* (서비스 시작), *Service stop*
(서비스 중지) and *Service restart* (서비스 재시작) from *Start reading* (읽기 시작).
While settings load, home explains waiting and the next step after completion;
if that state persists, close and reopen the app safely. Empty, error and document
preparation states show the corresponding next step instead of directing a
currently disabled Read action. This changes feedback, not service permissions,
readiness checks, saved settings, automatic initialization or Read behavior.

The v5 source observation was made before that component had a separately bound
build. Its feedback changes do not establish the cause of the original GUI
loading issue. Match a packaged app to its own guide and results. The current
home layout is described in *Home window* above.

= Isolated native fixture inspection <local-native-fixture-inspection>

Local fixture inspection uses only local document data and bundled math, without
a manager, account or inference provider. It is distinct from
#doc-ref(<managed-native-inspection>, "isolated-native-reader-inspection")[managed-service inspection].
For an explicitly prepared development app, the existing arguments
`--dev-root ABS --dev-no-activate --native-reader-fixture ABS` select a local
fixture and bundled mathematical runtime. The fixture must have fixture scope.
This path does not create a Reader manager or connect an editor, even through a
direct editor method. External Reader, browser/Homepage opening, file choosers,
log/settings reveal and external guide opening are disabled and reject their
callbacks. This includes Export PDF from an offline Original PDF snapshot: the
control and forced callbacks refuse destination selection and external writes.
Local PDF viewing and private Copy remain available. Home address, body and PDF
Copy use the private named pasteboard. Standard Cut/Copy/Paste in settings,
search and multiline input are refused at their responder in fixture mode.
Normal nonfixture editing and verified PDF export keep their existing owners.
The fixture's guide-opening menu is disabled; its guide is the same app bundle's
`Contents/Resources/UserGuide.pdf`.

Settings, recovery drafts, logs and startup timeline use the development root.
Fixture settings refuse a symlink or nonregular profiles file. Optional startup
diagnostics queue value-only file operations; initialization and shutdown do not
wait for slow or failed diagnostic I/O. This source repair does not establish
that the first native window opens successfully; that remains a same-computer
background-launch check for the new app and fresh fixture.
Necessary verification children receive a dedicated HOME, CFFIXED_USER_HOME,
TMPDIR, XDG_CACHE_HOME and FLOW_READER_DATA_DIR before starting. Math retains its
existing PATH-only environment with file writes and network access denied.
Fixture CLI access is limited to version, profiles, config validation and
nonexecuting launch-plan/agent-plist introspection; it cannot serve or control a
service. No global environment or OS appearance setting is changed.

The offscreen checks use a virtual ordinary home and injected external operations;
they do not certify a GUI launch or complete AppKit/LaunchServices-managed file
isolation. Platform caches, actual native input, VoiceOver and macOS 13 execution
remain separate acceptance gates. Use the exact source/app and fixture binding
from the current integration handoff; an old fixture/app is not current evidence.

The fixture keeps the existing local offline recovery library under its dev-profile
root, including saved drafts. Offscreen construction respects the existing
showNativeWindow input; it does not grant manager, editor or external effects.

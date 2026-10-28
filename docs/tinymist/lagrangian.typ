= Lagrangian

*Read and review live Typst documents on your Mac, phone, or tablet.*

Lagrangian is a macOS menu bar app that manages Typst projects and their live previews. Edit your source in your usual editor, then read the result in a browser, mark passages, and save selected text for a follow-up with Codex.

#link("flow-app.md")[User guide] · #link("examples/reading-demo.typ")[Try the reading demo] · #link("https://github.com/kimpossible-TY/Lagrangian/issues")[Issues] · #link("../dev-guide.md")[Development guide]

= What you can do

#table(
  columns: (1fr, 2fr),
  table.header([Feature], [How you use it]),
  [Live project previews], [Add a `.typ` entry file, then start, stop, or restart its preview from the menu bar. Saved source edits update connected viewers.],
  [Mobile reading and selection], [Open the project's configured HTTPS address on your phone or tablet. Select and copy text with the device's native selection handles.],
  [Source highlights], [Select a passage and choose *Highlight* (하이라이트). Supported selections are saved in the Typst source and appear in exports.],
  [Browser review marks], [Choose *Red strike* (빨간 취소선) for a temporary review mark. Undo or clear marks in this browser without changing source.],
  [Saved Codex context], [Choose *Save for Codex* (Codex 저장) to save selected text and location for a later question. A configured selection reader lets Codex use that context.],
  [Device document themes], [Choose System, Light, or Dark independently in each viewer. Documents that support the theme input change their native palette.],
  [Reference return], [Follow an equation, figure, or heading reference, then choose *Back to reference* to resume reading.],
  [Change navigation], [Reopen a preview at its latest rendered visual edit, or use *Jump to change* while reading elsewhere.],
)

#image("images/mobile-selection.png", width: 78mm, alt: "Flow reading demo in a phone-sized preview with selected text and the Highlight, Save for Codex, and Red strike toolbar")

The #link("examples/reading-demo.typ")[reading demo] in the actual preview frontend at a phone-sized touch viewport. The bottom toolbar appears when text is selected. See the #link("flow-app.md")[user guide] for each action's steps and conditions.

= Open your first preview

If Flow is installed, follow these steps. For a new Mac, use the #link("#first-install")[first-install instructions] below first.

+ Open `~/Applications/Lagrangian.app`.
+ Click *Add Project* (프로젝트 추가…) and select your document's `.typ` entry file. To try the features, select `docs/tinymist/examples/reading-demo.typ` from this checkout.
+ If the document belongs to a larger workspace, set *Project folder* (프로젝트 폴더) to its root. Add any required font or package folders, then click *Save settings* (설정 저장).
+ Click *Start reading* (읽기 시작). Flow validates and saves changed settings, starts the preview, and opens the browser when a document is available. Preparation progress and failures appear in the app window.
+ Save a source edit in your editor to see the preview update. Select a sentence to reveal the reading actions.

Closing the app leaves started previews running. Use *Stop* (중지) to stop a project and disable its automatic service startup. The app's *Usage, update and recovery guide* (사용·업데이트·복구 안내) menu opens the bundled PDF.

Keep the reading tab open through a temporary interruption: the reader reconnects while preserving the accepted content and selection. Flow checks service state after wake and network changes, reduces idle checks under battery or power constraints, and respects system sleep. See the #link("flow-app.md#resume-after-an-interruption")[resume guide] for recovery behavior.

== Read on your phone or tablet

Set up the project's Tailscale HTTPS route in Tail Hosting, enter that address in *HTTPS address* (HTTPS 주소), and save the project settings. Use *Copy address* (주소 복사) and open the HTTPS URL on a device with access to the same tailnet. Flow's local `127.0.0.1` address works only on the Mac running the preview; entering an HTTPS address in Flow does not create a route. Follow the #link("flow-app.md#read-on-a-phone-or-tablet")[mobile access guide] for the setup and checks.

= First install

Use macOS 13 or newer. App packaging requires the Swift compiler and Python 3. Cloning and building the preview frontend also requires Git, Node.js and Yarn; building the engine requires the workspace Rust toolchain.

On a fresh machine with no existing Flow engine, build the maintained frontend and engine:

```sh
git clone https://github.com/kimpossible-TY/Lagrangian.git
cd Lagrangian
yarn install --immutable
node scripts/build.mjs build:preview
python3 scripts/flow-app.py build --build-engine --jobs 2
python3 scripts/flow-app.py install dist/Lagrangian.app
```

The Rust toolchain is specified in `rust-toolchain.toml`. Use a native ARM Python environment on Apple Silicon. After installation, follow *Open your first preview* above.

If you already have a compatible `flow-engine` from a Flow bundle, you can package it instead:

```sh
python3 scripts/flow-app.py build --engine /absolute/path/to/flow-engine
python3 scripts/flow-app.py install dist/Lagrangian.app
```

This path needs the app packaging tools but does not rebuild Rust or the preview frontend. A compatible Flow engine supplies device themes, mobile selection, saved Codex context and change navigation. An arbitrary upstream tinymist executable is not assumed to supply these features.

= Update an existing installation

When `~/Applications/Lagrangian.app` already exists, the build reuses its engine by default. During the transition, it can also reuse the engine in the former `tinymist-flow.app` bundle:

```sh
python3 scripts/flow-app.py build
python3 scripts/flow-app.py install dist/Lagrangian.app
```

Use `--build-engine --jobs 2` after rebuilding the preview frontend when you also need engine or preview changes. App-only rebuilds with the installed engine keep its existing preview features. The installer preserves the previous bundle for recovery. See the #link("flow-app.md#update-and-recover")[update and recovery guide] for verification, rollback, signing and macOS consent.

= Development

This repository maintains the native app, tinymist engine, preview frontend, packaging, branding, tests, and documentation. Packaging can reuse a compatible external engine or build the maintained sources.

```sh
python3 -m unittest discover -s tests/flow-app -v
python3 scripts/flow-app.py verify dist/Lagrangian.app
```

For a release, pass `--version` with the intended release number and build from a clean commit. The manifest records the Flow source revision, engine provenance, build settings and signing mode. See the #link("../dev-guide.md")[development guide] for engine builds, validation and documentation generation.

== Repository

- `apps/macos/`: native app and Tail Hosting adapter.
- `scripts/flow-app.py`: build, installation, recovery, and migration.
- `tests/flow-app/`: app configuration and packaging recovery checks.
- `assets/branding/`: app icon and branding source.
- `docs/tinymist/`: canonical Typst documentation, generated web user guide, and reading demo.
- `openspec/`: app, engine, and preview behavior contracts.
- `crates/`: maintained tinymist engine and protocol implementations.
- `tools/typst-preview-frontend/` and `tools/typst-dom/`: preview frontend and document rendering.
- `editors/`: compatible editor integrations.

README is generated from `docs/tinymist/lagrangian.typ`; the web and bundled PDF user guides share `docs/tinymist/flow-app.typ`. Regenerate Markdown with `node scripts/link-docs.mjs` using an external `typlite` executable. The first Lagrangian launch migrates the former app's support and log directories and leaves compatibility symlinks at their old paths.

= License

Distributed under #link("../../LICENSE")[Apache License 2.0]. Powered by #link("https://github.com/Myriad-Dreamin/tinymist")[Tinymist] and #link("https://typst.app/")[Typst], with upstream notices retained.

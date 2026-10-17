User clarification, 2026-10-17: the mobile solution must make all essential content
readable directly in the body. Slides, horizontal movement, zoom, and extra clicks
to enlarge equations are not acceptable substitutes for responsive composition.
The existing scrolling and annotation-dialog prototype does not meet this contract.

- [x] Inspect current engine, preview, Flow profiles, Tail Hosting ownership, and PDE HTML failures.
- [x] Add isolated target-aware package adapters and a reproducible reader build command.
- [x] Compile the full PDE document with math, references, footnotes, and annotation adapters; verify graphical programs separately.
- [x] Evaluate automatic math line breaking against all 1,411 PDE display equations; record remaining overflow and fragment-identity issues.
- [ ] Separate mathematical content from mark/decoration SVGs and distinguish derivation alignment from matrix structure.
- [ ] Implement width-aware mathematical line breaking/alignment at the selected font size, preserving every term and reference.
- [x] Add coordinate-unit fitting, an automatic viewport/font request path, and per-canvas caching without editing authored CeTZ coordinates.
- [ ] Implement a shared width-aware CeTZ canvas adapter that preserves source coordinates, separates geometry scale from readable labels, and detects collisions before introducing necessary panel/legend layout rules.
- [ ] Show essential annotations and graphical relationships inline without reveal/expand actions.
- [ ] Load transport sections automatically in continuous vertical reading, without slide or next-section navigation.
- [ ] Enforce per-component layout checks: no required zoom, horizontal pan, expansion, clipping, or unreadable labels.
- [x] Add saved quotations with context-based relocation, cross-section navigation, and explicit ambiguous/missing states.
- [ ] Complete broader reading-position and selection update checks on actual PDE content.
- [x] Integrate saved-source recompilation, revision diagnostics, and Flow lifecycle.
- [ ] Verify reader at mobile widths and large font sizes against actual PDE content.
- [x] Expose an independent development Reader through Tail Hosting and Tailnet HTTPS.
- [ ] Connect the mobile entry and explicit view preference after fidelity validation, retaining the original view.
- [ ] Verify existing paged service and reader delivery, document operation and rollback.

Implementation checkpoint: the complete PDE document compiles to HTML with no
missing anchor targets, duplicate SVG IDs, unresolved annotation targets, or
unhandled compiler-loss warnings. All 15 graphical annotation programs render
against supplied term geometry; the browser verifies an actual PDE relationship
at normal and large font sizes. The reader loads one of 57 sections, preserving
cross-section references and reading keys. Saved highlights pass automated relocation tests and browser checks on a synthetic
fixture. Managed lifecycle and compiler-dependency watching are implemented and
tested. The separate managed PDE Reader completed its first accepted compilation after
the macOS Documents access wait resolved. The installed Reader update and Tail Hosting restart succeeded. Its separate
Tailnet HTTPS route is available. An intentional Reader-only exit recovered in
14.65 seconds while all original PDF checks stayed HTTP 200. Figure layouts,
offline delivery, and deployment validation remain unfinished. The Reader has its own HTTPS endpoint on port 23627. The original PDF route,
other services, and the mobile default are preserved.

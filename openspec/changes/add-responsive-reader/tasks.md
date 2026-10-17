- [x] Inspect current engine, preview, Flow profiles, Tail Hosting ownership, and PDE HTML failures.
- [x] Add isolated target-aware package adapters and a reproducible reader build command.
- [x] Compile the full PDE document with math, references, footnotes, and annotation adapters; verify graphical programs separately.
- [ ] Implement responsive Reader frontend, figure layouts, and local equation expansion.
- [ ] Preserve reading position, references, text selection, and highlights through updates.
- [ ] Integrate saved-source recompilation, revision diagnostics, and Flow lifecycle.
- [ ] Verify reader at mobile widths and large font sizes against actual PDE content.
- [ ] Expose a new Tailnet endpoint and connect the mobile entry while retaining the original view.
- [ ] Verify existing paged service and reader delivery, document operation and rollback.

Implementation checkpoint: the complete PDE document compiles to HTML with no
missing anchor targets, duplicate SVG IDs, unresolved annotation targets, or
unhandled compiler-loss warnings. All 15 graphical annotation programs render
against supplied term geometry; the browser verifies an actual PDE relationship
at normal and large font sizes. The reader loads one of 57 sections, preserving
cross-section references and reading keys. Figure layouts, persistent highlights,
offline delivery, and managed deployment remain unfinished. Tailnet routing and
the mobile default have not changed.

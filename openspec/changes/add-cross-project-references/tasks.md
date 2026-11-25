## Component deliverables
- [x] Specify IDE directory addition, stable project identity, preview interaction, navigation history and HTML metadata/fallback contracts.
- [x] Add backward-compatible Profile.projectRefKey decoding and validation.
- [x] Add deterministic directory entry discovery and directory registration without changing file-based addProject.
- [x] Implement bounded schema-1 catalog loading, explicit and PDF fallback resolution, local profile matching and navigation stack.
- [x] Implement the compact NativeAppDesign floating preview with interactive icon-only arrow.up.right control and body activation, composing an exposed .floating NativeDesignSurface inside NSView.
- [x] Register both sources exactly once and verify production sources with the two warning-denying Swift test harnesses.

## Verification
- [x] `/opt/homebrew/bin/python3 -B -m unittest tests/flow-app/test_project_service.py -v` — 27 tests passed; Swift 5 compilation with warnings as errors, no Swift warnings.
- [x] `/opt/homebrew/bin/python3 -B -m unittest tests/flow-app/native-reader-app/test_cross_project_preview.py -v` — 4 tests passed; Swift 5 compilation with warnings as errors, no Swift warnings. Covers native button/body hit testing and offscreen layout/painting in both appearances.

`openspec validate add-cross-project-references --strict` passed. These checks use isolated fixtures and do not install or restart the user's app or services.

## Follow-up integration outside this component change
These items are specified contracts and are intentionally not claimed as delivered runtime features by the component checks.
- [ ] Wire the IDE directory chooser and ambiguous-entry picker through the existing app owner.
- [ ] Wire first-click preview and committed second-click target project/anchor navigation in the existing reader owner.
- [ ] Compose back-stack commit/restoration with existing session adoption; verify failures preserve origin and history.
- [ ] Emit and consume HTML data-project-ref-* metadata with projects.json fallback in the existing producer/reader owners.
- [ ] Verify complete IDE, preview, project/anchor jump and Back paths on the integrated app version.

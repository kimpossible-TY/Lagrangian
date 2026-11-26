## Component deliverables
- [x] Specify IDE directory addition, stable project identity, preview interaction, navigation history and HTML metadata/fallback contracts.
- [x] Add backward-compatible Profile.projectRefKey decoding and validation.
- [x] Add deterministic directory entry discovery and directory registration without changing file-based addProject.
- [x] Implement bounded schema-1 catalog loading, explicit and PDF fallback resolution, local profile matching and navigation stack.
- [x] Implement the compact NativeAppDesign floating preview with interactive icon-only arrow.up.right control and body activation, composing an exposed .floating NativeDesignSurface inside NSView.
- [x] Register both sources exactly once and verify production sources with the two warning-denying Swift test harnesses.

## Verification
- [x] `/opt/homebrew/bin/python3 -B -m unittest tests/flow-app/test_project_service.py -v` — 28 tests passed; Swift 5 compilation with warnings as errors, no Swift warnings.
- [x] `/opt/homebrew/bin/python3 -B -m unittest tests/flow-app/native-reader-app/test_cross_project_preview.py -v` — 13 tests passed; Swift 5 compilation with warnings as errors, no Swift warnings. Covers native button/body hit testing and offscreen layout/painting in both appearances.

- [x] `/opt/homebrew/bin/python3 -B -m unittest tests/flow-app/test_flow_ui.py -v` — 21 tests passed, including IDE directory registration, cross-project navigation/session lifecycle and home-minimal controls; no Swift warnings.
- [x] `/opt/homebrew/bin/python3 -B -m unittest tools/flow-reader/tests/test_sections.py -v` — 10 tests passed.
- [x] `/opt/homebrew/bin/python3 -B -m unittest tests/flow-app/native-reader-app/test_contract.py -k LabelContractTests -v` — 4 tests passed, including duplicate-ID rejection and real compiler label preservation.
- [x] `PYTHONPATH=tools/flow-reader /opt/homebrew/bin/python3 -B -m unittest tools/flow-reader/tests/test_cross_project_refs.py -v` — 11 tests passed.

`openspec validate add-cross-project-references --strict` passed. These checks use isolated fixtures and do not install or restart the user's app or services.

## Completed follow-up integration
These contracts are wired through the existing owners and covered by integrated headless CLI tests. Live macOS GUI E2E Pass 4 was previously reported complete; it is retained as prior acceptance evidence and was not rerun for this merge.
- [x] Wire the IDE directory chooser and ambiguous-entry picker through the existing app owner.
- [x] Wire first-click preview and committed second-click target project/anchor navigation in the existing reader owner.
- [x] Compose back-stack commit/restoration with existing session adoption and exact scrollOffset restoration, clearing anchor when blockID is non-empty; verify failures preserve origin and history.
- [x] Emit and consume HTML data-project-ref-* metadata with projects.json fallback in the existing producer/reader owners.
- [x] Verify complete IDE, preview, project/anchor jump and Back paths on the integrated app version, including the previously reported live macOS GUI E2E Pass 4. Verify this merge solely via headless CLI unittest and strict OpenSpec validation.

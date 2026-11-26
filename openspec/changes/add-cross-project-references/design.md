## Context and Scope
ProjectService owns project creation and persistence; Profile owns validation. CrossProjectCatalog owns read-only identity resolution; CrossProjectNavigationStack owns return locations. NativeCrossProjectPreviewView presents an already resolved preview and emits an explicit callback. Existing reader/session owners retain document adoption, service lifecycle, source authority and location restoration.

## Directory registration
The IDE directory action supplies a directory, optional entry and optional projectRefKey to ProjectService. Discovery returns relative regular .typ paths from the root and two nested directory levels, excludes hidden directories and symbolic-link directories, and sorts root main.typ first then lexically. Without an explicit entry, root main.typ wins; otherwise a sole candidate wins. Multiple candidates require an explicit chooser selection. No candidate raises FlowError. An explicit entry must identify a regular .typ file inside the registered root, including after symbolic-link resolution. Selection/validation failure saves nothing. Defaults, first unused port, supplied user home and existing profiles are preserved; directory registration saves once and selects the new profile. The existing file-based addProject API remains unchanged.

Profile.projectRefKey is optional and legacy JSON decodes its absence as nil. Nil and empty mean unconfigured; a non-empty value must match `^[a-z0-9][a-z0-9-]{0,63}$` over the whole string. Existing profile validation remains in force.

## Catalog and target identity
projects.json is UTF-8 JSON: `{ "schema": 1, "projects": { "project-key": { "title": "Title", "pdf_url": "https://example.test/book.pdf", "references": { "label": { "page": 3, "text": "Theorem 1", "x": 0.2, "y": 0.4 } }, "ambiguous_labels": [] } } }`. Coordinates are optional, finite values; pages are positive and one-based. Loading is local and capped at 16 MiB by default; unsupported schemas and oversized input fail.

Explicit project key and label resolution takes priority over fallback. Labels declared ambiguous never become unique. Fallback parses `pdf_url#page=N`, requires exact PDF URL and page, and, when display text is available, matches entry.text or `entry.text + " of " + project.title`. All remaining candidates produce unique, ambiguous or unresolved results deterministically. No first-match navigation is allowed. Explicit profile.projectRefKey wins. Otherwise unconfigured profiles may match a case-insensitive folder basename or profile name, normalizing whitespace, underscores and hyphens to a single hyphen. Empty or normalization-empty catalog keys never match a profile. Duplicate profile matches return nil rather than guessing.

## Preview and navigation
Compose `final class NativeCrossProjectPreviewView: NSView` with an exposed `let surface = NativeDesignSurface()` child whose role is `.floating`, following NativeFloatingCapsule. NativeDesignSurface remains final and NativeAppDesign supplies its current shared tokens. The embedded surface supplies NativeAppDesign palette and floating shape; label typography and layout use the shared typography and spacing constants. Native button hit testing stays intact while header, snippet and padding dispatch body activation once.

The first reference click shows a compact preview without switching projects. Header text is `projectTitle · referenceText`; the bounded snippet and truncated flag describe the available excerpt. The interactive NativeDesignButton has identifier `crossProjectPreview.open`, empty title, image-only SF Symbol `arrow.up.right`, tooltip and accessibility label `해당 문서로 이동`; no visible `열기` text is allowed. Both button activation and a second click on the preview body emit the same content through onOpenTarget. Use NativeAppDesign floating palette, spacing and shape. Preview construction itself never navigates. Snippet loading may attach through the existing managed client and start the target project's reader service; disposing the preview client does not stop that shared service. The initial catalog snippet remains available if loading fails.

The integrating reader validates the chosen target, pushes the origin profileID, documentTitle, anchor, blockID and scrollOffset only for a committed cross-project jump, and adopts the target project/anchor through existing session operations. Failed or cancelled jumps preserve the origin and stack. Back uses peek/pop with the same adoption rules, restores the saved location, and uses the fixed action label `돌아가기` (documentTitle remains stored return metadata). The value stack retains at most 64 entries by default, evicts oldest entries, supports smaller capacities and treats non-positive capacities as disabled. Changing capacity trims immediately.

## HTML interoperability
HTML links should carry `data-project-ref-project`, `data-project-ref-label`, `data-project-ref-text` and `data-project-ref-title`. The `data-project-ref-*` identity metadata is preferred. Only links without explicit identity use projects.json fallback based on PDF URL, page and display text. An ambiguous explicit identity suppresses activation without a separate failure display. An unresolved explicit identity, including unavailable catalog loading, opens the original URL only if it passes the existing external-URL safety policy; fragment-only or unsafe URLs do nothing. Explicit identity never falls back to guessing another catalog target from the PDF URL. This records current behavior, not a new reference-not-found UI. Neither path creates source coordinates or write authority. The integrated HTML producer and native reader consume this metadata through their existing owners.

## Verification and integration limits
Compile production core and preview components with `/usr/bin/swiftc -swift-version 5 -warnings-as-errors`. Temporary-directory tests cover legacy decoding, key validation, discovery, registration defaults/failures, catalogs, identity ambiguity, bounded navigation, actual AppKit controls, offscreen layout and both activation paths. The manifest must cover every production Swift file exactly once. Integrated CLI tests also cover IDE registration, reader jump/Back session adoption, exact scroll restoration and HTML metadata/fallback. The previously reported live macOS GUI E2E Pass 4 remains prior acceptance evidence; this merge is verified solely with headless CLI unittest and OpenSpec validation.

## Session and consent corrections
A new explicit Read and profile selection reset the Back stack. Empty profileID
origins are never pushed. Back discards missing or non-unique profile entries and
tries the next retained entry; a real target's failed navigation preserves that
entry. Cross-project candidates reserve only the target editor descriptor. The
origin window's consent tracking stays intact until windowInitialized commits.
Failure/cancel returns the reservation to consentedEditors; successful adoption
moves consent tracking to the new window.

## Native wire and HTML label export
The optional link-node projectRef value is `{project,label,title?,page?,text?}`;
project and label are non-empty and page, if present, is positive. Invalid metadata
raises invalid-project-ref. Repeated exported anchors raise duplicate-anchor and
reject the entire candidate. No separate projectRef capability is currently
negotiated: older strict nativeWireKeys decoders reject the new key, so backend
and app must be delivered together. This does not promise mixed-version support.

The Typst HTML producer wraps labeled headings, figures and equations with
`div[data-flow-label]`, excluding private prefixes flow-native-annotation-,
local-scope-, mannot-scope- and _mannot-. HTML normalization unwraps a label-only
wrapper with one element child and no non-whitespace text/comments; id and
label attributes transfer only when the child lacks them. Existing child
attributes win conflicts. Section/native export retains user label anchors
separately from DOM ids; first label ownership avoids duplicate exported ids.
Native duplicate-anchor rejection still applies to remaining duplicate DOM ids.

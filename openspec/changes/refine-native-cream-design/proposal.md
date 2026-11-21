## Why

Lagrangian needs a coherent native macOS research-notebook identity: cream paper,
fine round marker strokes, and the user's exact existing logo. The earlier SCSS
request expresses reusable components and state tokens; the corrected target is
the AppKit app. Existing content, service and effect owners must remain intact.

## What Changes

- NA18 adds reusable opaque AppKit surfaces, semantic button paint, chrome
  typography, preference-aware colors, and an exact three-layer vector adapter.
- NA19 applies these components to home/settings, reader and conversation
  chrome, and implements the selection capsule using existing guarded operations.
- NA20 will register new sources and assemble an isolated development app.
- Independent review, regression, documentation and actual GUI acceptance remain
  separate follow-up gates. NA18 is source-component evidence only.

## Capabilities

### New Capabilities

None.

### Modified Capabilities

- `flow-macos-app`: reusable native chrome, exact brand geometry and accessible
  preference/state presentation on macOS 13 and later.
- `native-reader`: presentation-only adoption boundaries, guarded capsule/composer
  behavior and explicit evidence separation.

## Impact

NA18 adds only NativeAppDesign.swift, NativeBrandMark.swift, focused tests and the
new canonical `docs/tinymist/dev/native-cream-design.typ` with this design delta.
NA19 applies these components to current app composition; source registry remains NA20-only. No HTML, DOM,
WKWebView, SCSS pipeline, document/PDF/math paint or new credential/effect owner.
Existing `implement-native-reader-app` artifacts remain untouched.

## Non-goals

Deployment, main/push/CI, app activation, installation, service changes, Rust
builds, authentication, live inference, whole-product or macOS 13 runtime acceptance.

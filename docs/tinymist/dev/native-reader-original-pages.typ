#set page(paper: "a4", margin: 16mm)
#set text(size: 10pt)
= Native original PDF pages — NA12

== Publication

`server/native_pages.py` reuses `AcceptedSnapshot.capture/current` and
`Project.execute` with PDF CompileRequest. The saved HTML dependency set and
additional PDF dependencies stabilize before publication. Signatures and content
fingerprints are checked again under the publication lock; compilation is outside
that lock and outside the UI thread. Failure retains the last immutable PDF.
The service-bound publication incarnation and monotonic sequence bind accepted
revision, union/HTML/PDF input fingerprints, PDF SHA256 and byte count. Client byte
echoes do not authorize publication.

The existing scoped HTTP handler exposes `api/native-pages` and its exact returned
resource `api/native-pages/<publicationID>/<sequence>.pdf`. It retains registered
document prefixes, Host/Origin, native UUID/schema/capability and payload guards.
The capability is `original-pdf-full-v1`. Delivery is immutable PDF full snapshot
and reset. Raw engine diff-v1 native consumption is unverified.

== Native composition and limits

`NativeReaderOriginalPageTransport.swift` validates server metadata and resource
bytes. Local PDF geometry inspection does not establish source authority.
`NativeReaderOriginalPageView.swift` paints one viewport through the private serial
PDFKit worker in `NativeReaderPagedLayout.swift`. Original pages and NSTextView
reflow share the canonical semantic store and Session.PreparedAdoption while
retaining separate geometry, local selection and copy meaning. Only actual paint
in the visible mode acknowledges Read. Hidden reflow paint cannot acknowledge a
page. Failed candidates retain accepted content; selected pages hold replacement
until explicit release. Cancel/dispose reject obsolete completions.

PDF bytes are limited to 16MiB, geometry to 2048 pages and reachable PDF objects
to 100000. Production prepares geometry without eager raster/text/character boxes.
Raster cache retains at most three entries and 16MiB; text cache retains at most
eight pages and 1MiB, with at most 250000 UTF16 units per page. Search scans pages
incrementally, with a 256-unit query, at most 256 results, a 4Mi-unit scanned-text budget and a cooperative five-second deadline. Exceeded bounds are
explicit failures. Internal PDFKit allocations are separate from these cache
counts and are observed through process peak RSS. The old eager component path
remains bounded to 32 pages and is not long-document acceptance evidence.

== Actions and recovery

URI and GoTo annotations become inert values. Explicit native callbacks accept
only validated HTTP/HTTPS/mailto without credentials or controls, or finite,
in-range destinations in the same artifact. No PDFView action dispatcher,
JavaScript, forms, launch, remote file or embedded-file actions run. PDF text and
bounding boxes are display/search evidence, never source ranges or glyph-cluster
authority. Source anchors remain explicitly unsupported by this page contract;
prebuilt engine probes document their actual tested scope. Hidden reflow source,
highlight and chat actions are guarded. Verified native reflow actions retain
their existing owner.

Optional PDF/viewport recovery supplements the existing typed atomic recovery
store, hash checks, permissions and budgets. It includes accepted bytes and
matching identity/input/digest/page/scale, no credentials or additional source
excerpts. Old schema1 defaults and pending question/model limits remain. Offline
restore uses prepared adoption and stays read-only.

== Verification and delivery boundary

`test_original_pages.py` compiles current sources plus the two real new Swift files
explicitly with Swift5, warnings-as-errors and macOS13 target. Actual compiler
fixtures and owned temporary scoped HTTP connect transport, session and offscreen
native paint. A 256-page fixture measures far navigation/search/bbox/zoom/recovery,
render count, cache eviction/bytes and peak RSS. Host/Origin, input/dependency/PDF
tamper, stale/failure/restart, link and lifecycle negatives are separate checks.
All evidence lives in `test-output/page-service/NA12` on DevSSD.

During the historical C/NA12 page-component assignment, source registry and
delivery belonged to D/NA13 and NA06 integration. At fixed input09c5186b the two page
files and backend are registered and staged. Review-fix source changes still
require a newly bound app from the delivery owner. Headless pixels, private clipboard and zero
visible windows do not establish real GUI, VoiceOver, macOS13 runtime, source
mapping, complete application or delivery acceptance.


Native original pages use an NSScrollView viewport over the single page document
view. Document extent follows the prepared raster at logical zoom; viewport width
changes fit preparation independently, so zoomed page bottoms remain reachable.
Recovery retains bounded unscaled page-display offsets with optional old-schema
defaults, clamps them to the restored viewport, and does not create source ranges.
Pointer release checks the original snapshot/page/operation before selection.


== Observable page selection, AX and viewport limits

Display selection is on one current page only. PDFKit character count must equal
UTF16 length for selection. Endpoints must be extended-grapheme boundaries and
the extracted string must exactly match. Rectangle selection must produce exactly
one text range; ambiguity is unsupported. PDF display offsets never grant Typst
source authority. Current-page bounded AX text/ranges/selected range and safe link
children are scoped to accepted snapshot, page, view generation and operation.
Old children cannot act after replacement, navigation, cancellation or hiding.
Tab/Enter reaches safe links; Cmd-A and copy remain page-display operations.
This internal implementation is not actual VoiceOver speech acceptance.

Geometry coordinates/sizes have absolute value at most 4096, rotation is only
0/90/180/270 and crop must lie within media. Zoom 0.1–8 is necessary but not
sufficient: a requested raster has each side at most 8192 and at most 4,194,304
pixels (16MiB RGBA). Unsupported text/geometry or exceeded budgets are explicit,
not placeholder success. One page's AX text is exposed rather than an eager
256-page accessibility tree; existing worker caches retain their independent
three-raster/eight-text-entry bounds.

Find selection bounds and same-artifact GoTo points are transformed by the
existing crop/rotation/zoom geometry owner and revealed in the actual clip
viewport after matching raster installation. Deferred reveal is cancelled on a
superseding page/operation/cancel; callback/page-index success alone is insufficient.
Exact in-flight page-preparation ticket/binding reuse is idempotent. Consumed,
cancelled, older-generation or different-binding tickets do not regain authority.

Offline reflow restoration explicitly supplies validated snapshot assets to the
same fallible atomic prepare/adopt path and never requires live target/network/
assets. Assets become accepted only after adoption; source/chat remain read-only.
The enclosing typed recovery selection cap of32 and reflow zoom 0.5–4 still apply,
independently of local selection of33+ fragments and0.25 display zoom. Those larger display states are
not silently converted to supported saved state; complete app resume remains an
independent gate. The 256-page evidence is a synthetic compiler fixture, not a
claim about arbitrary documents, full fidelity, real GUI or OS13 execution.


== Native link traversal, recovery and export

Tab moves within current-page typed links; at the last link it delegates to the
window's next eligible key view. Shift+Tab at the first delegates to the previous
key view. One-link and multi-link offscreen key loops are distinct from actual
GUI routing, Full Keyboard Access and VoiceOver; stale page AX/actions still fail.
PDF recovery retains publication/input/digest/page/scale/unscaled offsets only,
not display selection, and offline mode switching is unsupported. The reflow
selection32/zoom0.5–4 storage bounds do not describe PDF selection storage.
Explicit Export PDF saves the accepted publication's original validated bytes via
native chooser and existing RecoveryStore staging/atomic publication. Native
Production PDFKit reopens staged bytes; the test separately reopens published
output bytes. No screenshot, regenerated PDF, recoloring or
PDF-to-Typst source promotion occurs. Cancel/stale/dispose/tamper/destination
failures preserve previous files in the tested precommit paths. Observed
directory identity/metadata fingerprint mismatches reject commit; same-metadata
content changes and external rename races are not a stronger atomic CAS guarantee. Reflow display preview is a separate owner from
PDF width-fit/scale and its selection-hold/raster budgets.

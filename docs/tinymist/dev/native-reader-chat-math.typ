#set page(paper: "a4", margin: 16mm)
#set text(size: 9pt)

= Completed answer native math — NA10

This component consumes base `882e3ea48044eeeae95ad34e4c97f1319797af8c`.
The inherited `1eb9` contract is prior art. Shared schema, source permissions,
host, runtime producer, source list and packager remain with their existing owners.
This is headless component evidence, not application or shipping acceptance.

== Host composition and lifetime

NA06 constructs `NativeMathWorker(node:helper:runtime:timeout:record:)` with trusted,
verified offline URLs. The helper must be the final NA10 bytes, not NA11's frozen
`helper.mjs`. Inject it with
`try chatView.configureMath(worker: worker, context: objectContext)` before presenting
history. The `NativeObjectContext` identity must equal the chat request target and
snapshotGeneration must equal its request generation. Use an exact context for
width, font size/name, theme and layout generation; call configureMath again after
any of these changes. Dispose the view on context replacement. This is the minimum
NA06 injection; NA10 does not modify the host.
The answer text view adopts the explicit light/dark appearance with the same context
so cached glyph ink and surrounding native text have consistent contrast.

`present` schedules a detached bounded transcript preparation, never a process,
SVG decoder or layout on MainActor. Only complete assistant messages prepare math.
The view's synchronous renderer consumes immutable images and metrics. Identity
contains request/view/target/generation, conversation/message IDs, version, sequence,
exact text/completion/role and the full object context. Duplicate presentations
coalesce, including failures. Cancellation, replacement and disposal increment an
epoch before cancelling the detached job; obsolete results cannot adopt. One job
per view and two active calculations per worker; overload rejects without a queue.
The compatibility `NativeReaderAnswerPart.attributed(..., math:)` operation expects
immediate immutable cache lookup only. The chat view uses the typed worker API.

Transcript parsing preserves exact authored token bytes. Matched single dollars
and backslash-parentheses are inline; matched double dollars and backslash-brackets
are display. Inline math cannot cross a newline. Backtick spans/fences shield math;
backslashes escape the following character. Unclosed delimiters/code remain literal
through the end, without reinterpreting their contents. Failed TeX remains literal
with a bounded AX diagnostic and does not count as a prepared formula. Streaming
and user messages remain literal. Messages over 80000 UTF8 bytes retain full literal text without math parsing. No inferred source range, verified Typst copy,
source highlight or compiler authority is granted to answer mathematics.

== Computation contract

Legacy JSON `mathML` requests and version-1 SVG/metrics responses remain accepted.
Explicit `kind: "mathml"` is equivalent. The additive discriminant `kind: "tex"`
requires `tex` and Boolean `display`, and rejects `mathML`. Both use width 16–8192,
fontSize 8–96, font `MathJaxNewcm` and revision/generation/theme context. The Swift
layout context has the existing stricter minimum width 64. TeX responses add kind,
trimmed normalizedTeX, actual serialized normalizedMathML, semanticText and display.
The original untrimmed input SHA binds the existing layout validator; response
context/width/font metrics must match. Semantic text describes fractions, roots,
scripts and matrix rows, independently of glyph paths. It is a deterministic
structural description, not a general mathematical speech engine.

The TeX input imports only `@mathjax/src/js/input/tex.js` and explicit
`@mathjax/src/js/input/tex/ams/AmsConfiguration.js`, with packages base/ams.
`SerializedMmlVisitor` serializes the real compiled tree; the existing MathML input
and SVG output render it. Pinned AMS transitively imports its NewcommandUtil/Items/Methods/Mappings/
Configuration files; these are recorded dependencies, not an enabled user macro
package. The five exact transitive names are checked separately, and user definition
commands still reject. The closed command/environment vocabulary lives in
`math_layout.mjs`. Require/autoload, HTML, external resource commands, user macros,
macro definitions, control-sequence construction and unknown commands reject before
parsing. No document-supplied module/options/font path is accepted. Dynamic loads
are confined to pinned NewCM SVG glyph modules within the verified runtime tree.
Unsupported glyphs emitting text/resources reject; no system-font paint fallback.

Limits: request 256KiB, source 64KiB, TeX 16384 UTF16 units/8192 tokens, braces and
semantic depth 64, semantic nodes 4096, macro-template substitutions 1000, fragments
256, output 8MiB, stderr 64KiB. Worker deadline defaults to 10s, clamped 0.1–30s;
cancel/deadline/budget failure terminates only its child. Node old-space is 128MiB,
stack 1MiB. Resident memory is sampled every worker polling interval (5ms) and
exceeding 256MiB terminates the child; brief sampling overshoot is possible. Native images are at most 4096pt and four million pixels; transcript
retains at most 16MiB of prepared pixels, 64 formulas, 256 messages and 512KiB of
text. No unbounded cache. The worker's sandbox denies network and all file writes.
Do not nest an outer sandbox around it (sandbox_apply error 71).

Native boxes include baseline zero even when SVG ink has negative descent, fixing
bare inline x through the unchanged MathML API. MathJax's exact root style
`vertical-align: 0` is also accepted; all other unexpected styles still reject.
Cyrillic Ж and Greek α use the pinned NewCM SVG paths and dynamic Cyrillic table.
This proves those tested scalar/glyph cases, not full Unicode, shaping, bidi,
font substitution, general linebreaking or all mathematical fidelity.

== Copy, accessibility and effects

The native attachment retains immutable pixels and baseline metrics. Its plain
copy attribute contains original TeX delimiters. `NativeReaderAnswerTextView`
implements ordinary string pasteboard copy and exposes structural transcript text
through headless accessibilityValue. Tests use only a private pasteboard. VoiceOver
navigation and real GUI use remain independent gates. No user clipboard is read.

Preparation, redisplay, theme/resize, copy and AX have no inference/provider/source
operations. Explicit Send and the existing actions actor retain UUID deduplication,
lost-ack/history reconciliation, draft edit protection, cancellation and SSE context
guards. Existing service regressions validate fake-provider dispatch separately.

== Verification and runtime handoff

Run `python3 -B -m unittest discover -s tests/flow-app/native-reader-app -p test_chat_math.py -v`.
All new commands, inputs, before/after source hashes, worker exits, native PNGs and
test reports are retained below DevSSD `test-output/chat-math/NA10`. The independent
expect fixture specifies hierarchy, scalars, fraction numerator/denominator/bar
topology and broad em metric bounds. The authored Typst oracle is separately
compiled; its output is not copied into expected MathJax metrics. Swift compiles
for arm64 macOS13 with warnings as errors; this is not macOS13 runtime execution.
Failure adapters are explicitly slow/flood scripts, separate from real positives.

Use only NA11's verified package tree at `build/runtime-producer/NA11/runtime`,
manifest SHA `e2fbdb745477db56a4a6505503656cd64d27ad9e13c428c395ec46537c531eb7`.
Its old helper SHA remains `1714ee230d1e12ddefc4c7160fdccd6a353a6123a2d340ae47c64ab227559c4d`.
New helper execution remains in this worktree/new evidence. NA08 must rerun the
existing runtime producer with final committed helper bytes, entrypoint
`node --max-old-space-size=128 --stack-size=1024 helper.mjs --runtime ROOT`, and
the retained TeX module inventory/digests. No dependency/version/lock changes or
new install are required. Old stage bytes remain immutable. Offline relocation,
final runtime payload and installed app paint must be rebound to the new helper.
The current host-required Node 26.13.1/library closure is not macOS13 shipping proof.
Host injection, final runtime rebinding, GUI/VoiceOver and full fidelity remain open.

== PM-CHAT-PAINT-01 correction and evidence boundary

The initial `final/transcript.png` contained a dark background and Assistant heading
only. Its earlier passing assertion counts and isolated formula paint did not prove
transcript paint. The later minRGB-less-than-100 crop check was also invalid: it
counted dark background as ink. Both claims are withdrawn. The interrupted CLI exit
1 was a PM SIGINT at a completed tool boundary, not a quota/429 result. Historical
artifacts remain immutable; corrected evidence is under `chat-math/NA10/v2`.

The harness had resized the child text view without the production scroll/stack
hierarchy's normal layout. The corrected native-only reproduction places the actual
NativeReaderChatView hierarchy in an offscreen NSWindow, never ordered or activated.
Window/stack/scroll layout supplies the answer's viewport and text-container width;
the harness does not set child frames/container sizes or paint formula images into
the capture. It captures the actual clip view, including its text/attachment draw
and clipping. This resolves the harness geometry defect; the production scroll
hierarchy did not require a replacement. A separate production contrast defect in
the role heading is corrected by explicitly applying the dynamic label color.

Both theme PNGs are persisted, then decoded again for verification. The empty text
view at identical theme/viewport supplies the background. Pixel/view scale, flipped
glyph location and clip-relative top-left bitmap rows are explicit; attachment
glyph locations already include their baseline offset. Alpha-composited luminance
must differ from the background in the correct foreground direction. Five native
attachment regions and a separate body-text region exclude the heading. The actual
fraction region must contain a continuous rule and foreground on both sides.
Empty, heading-only and geometry-preserving missing-draw attachment mutants use
the same hierarchy/background and must all fail the identical checker in each theme.
No threshold applied to the dark background can establish success. The final light
and dark PNGs are also opened directly before binding the result to the commit.


== Adjacent answer-token copy

Ordinary answer copy restores authored delimiters separately for every selected
attachment/token, preserving count and reading order even for two or more adjacent
identical formulas. Equal original strings are not token identities. Full and
partial private-pasteboard selections, mixed formulas and prose are separate
regressions. This is authored answer copy, never verified Typst source copy.
Historical NA10 component evidence above remains tied to its original revision;
new review-fix copy assertions do not turn headless pixels into GUI/VoiceOver or
restaged delivery acceptance. The current host is27.2.1, target13; actual OS13
and live provider/account remain unverified.

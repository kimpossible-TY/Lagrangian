# Design

## Output and ownership

Use Typst's HTML target for semantic text and mathematical output. Add target-aware compatibility adapters for the PDE common packages. Preserve the source documents and existing package installation; build reader adapters into an isolated package overlay with recorded provenance. Any compiler modifications must be explicit, pinned, and tested independently.

The reader frontend and its asset/compile service live under `tools/flow-reader`. Existing engine compilation is the initial integration boundary. Flow supplies project root, entrypoint, fonts, and packages; Tail Hosting supplies HTTPS ingress. A separate reader process may be used during rollout so reader failures cannot interrupt the paged service.

The initial managed rollout uses a Reader lifecycle helper within this repository.
It reads the installed Flow app's profile export; only the parent ID, Reader port,
public URL, compiler and Python paths are stored separately. A clean-commit
installer archives immutable Reader releases under Flow's application support
directory. Its LaunchAgent has a distinct label and directly execs the Reader
process, so listener ownership can be checked without touching the paged job.
Tail Hosting consumes the helper's compatible profile/control interface and
reports the Reader's compile state separately from HTTP reachability. This does
not require replacing the installed native app or engine during rollout.

## Fidelity

Page-relative annotation packages cannot run unchanged in HTML. Represent marked mathematical terms and annotation text as linked semantic content. Preserve custom graphical relationships through faithful rendering or explicit adapters. Never silently discard an annotation or mathematical decoration to obtain a successful compile.

Replace decorative blocks with semantic HTML containers so nested equation labels and references remain visible to the document introspector. Keep theorem kinds, counter resets, and target-location numbering. Use MathML where faithful and SVG for unsupported mathematical constructs. Figure panels stack at narrow widths; vector scaling alone is insufficient when it makes labels unreadable.

## Reader protocol

Every published document snapshot carries a revision and diagnostic status. Failed compilation leaves the last successful snapshot visible with a stale/error indication. Stable labeled block identities, with deterministic fallback matching, anchor the reading position and persisted highlights. Do not replace the active document while the user has a selection or open annotation.

Use content and asset requests on the reader's own origin. The original paged view remains reachable from the reader. Initial mobile routing must honor an explicit choice and offer both views.

Partition the accepted HTML at top-level block boundaries. Keep every annotation
in the same section as its preceding marked terms. Assign reading keys globally
before partitioning; the manifest maps native anchors and reading keys to their
sections. Fetch only the displayed section and a bounded cache of recent HTML.
Keep large SVG and raster images as separate unchanged assets, with SVG hyperlinks
remaining inline. Revision-specific requests reject stale revisions.

For graphical annotations, the browser measures cloned marked terms in an
expanded equation scene. The service passes only validated numeric geometry to
the original CeTZ program and returns its overlay. A source fingerprint belongs
to the accepted snapshot, not the latest failed compile. Cache by revision and
geometry, namespace SVG identifiers, and reject uncached requests after source
changes. The first implementation uses an isolated full compile; a persistent
compiler can later reduce its latency without changing this protocol.

## Validation and delivery

Compile the complete PDE project, checking unresolved references and unsupported output diagnostics. Compare paged output before/after adapter changes. Browser verification covers 320, 390, 430, and 768 CSS-pixel viewports, larger fonts, light/dark themes, navigation, selection, updates, and offline reload where supported. Verify the original live service and new Tailnet reader endpoint independently before changing mobile entry behavior.

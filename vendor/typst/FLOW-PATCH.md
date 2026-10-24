# Local Typst core patch

Imported `crates/typst/src/lib.rs` and the original crate manifest from
Myriad-Dreamin/typst commit `59b5999da8e74e74583069408d2564fc1f9bc973`
(tag `tinymist/v0.15.1`), the existing Cargo.lock revision. Upstream README
and Apache-2.0 license are preserved (README trailing whitespace is normalized). Package identity and version are unchanged;
the manifest uses this workspace's already-pinned sibling crates.

Layout history retains the existing shared introspector for HTML and paged
documents instead of retaining complete output trees. All iteration introspectors
remain available for convergence failure diagnostics. Unknown Output types retain
their original complete output. No public trait, iteration limit, cache policy,
export behavior or tracing contract changes.

The compiler loop remains upstream's single implementation. Tests compare it to
full-output retention and independently check output ownership release. Changes
to this patch must run the core tests, native/WASM consumers and identical-input
browser comparisons. Rebase against the recorded upstream source when updating.
Released output ownership does not imply that memoization references disappear or
that allocated WASM linear memory shrinks.

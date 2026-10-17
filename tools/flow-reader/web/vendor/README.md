# Local mathematical renderer

`mathjax-4.1.3/` contains unmodified distribution files from `mathjax@4.1.3`
and `@mathjax/mathjax-newcm-font@4.1.3`. Both package manifests declare
Apache-2.0; the upstream MathJax license text and both complete package manifests
are retained. Font binaries, including their embedded notices, are unmodified.

Only the MathML/CHTML bundle, native assistive MathML extension, and New Computer
Modern CHTML font assets are included. `manifest.json` identifies the npm
archives and SHA-256 of each retained file. The Reader serves only these listed
files, using the versioned URL for cacheability. There is no CDN dependency.

Keep these distribution files verbatim. Update the versioned directory and
manifest together when changing renderer versions, then repeat the corpus,
selection, annotation, asset-delivery, and accessibility checks.

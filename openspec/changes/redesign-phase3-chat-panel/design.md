## Context

Shared Reader tokens provide theme, material and motion roles. Summary extraction belongs to reader-common; HTML renders the resulting text as textContent.

## Decisions

Use solid theme surfaces for the transcript and a solid baseline for the heading and composer, enhanced with frosted material when supported. Reduced transparency and increased contrast restore solid chrome. Controls use opaque hover fills, visible focus and mobile touch targets. Preserve the outer panel and summary geometry used by placement.

Strip paired unescaped bold delimiters alongside math delimiters before summary truncation. Preserve unmatched and escaped markers and existing currency handling. The controller consumes the shared result without parsing it again.

## Risks / Trade-offs

CSS glass is a web approximation. Static color tests do not establish rendering, interaction or device behavior; PM owns browser screenshots and visual review.

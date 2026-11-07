## Context

Shared Reader tokens provide theme, material and motion roles. Summary extraction belongs to reader-common; HTML renders the resulting text as textContent.

## Decisions

Use solid theme surfaces for the transcript and a solid baseline for the heading and composer, enhanced with frosted material when supported. Reduced transparency and increased contrast restore solid chrome. Controls use opaque hover fills, visible focus and mobile touch targets. Preserve the outer panel and summary geometry used by placement.

Strip paired unescaped bold delimiters outside inline code and math regions before removing math delimiters and truncating. Require non-whitespace inside delimiters and word boundaries around underscores. Preserve unmatched and escaped markers, code and existing currency handling. The controller consumes the shared result without parsing it again.

## Risks / Trade-offs

CSS glass is a web approximation. The header and composer sit over the opaque panel, so blur shows little; the glass is a material cue, not see-through. Static color tests do not establish rendering, interaction or device behavior; PM owns browser screenshots and visual review.

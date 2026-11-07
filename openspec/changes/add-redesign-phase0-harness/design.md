## Context

Homepage and Reader have isolated browser fixtures. Their static shells and rendered content have different lifetimes, so static checks cannot establish dynamically generated structure.

## Goals / Non-Goals

- Check stable shell hooks from source and dynamic hooks after fixture rendering.
- Capture the three representative states at two viewport sizes and two themes with pinned browser settings.
- Keep visual differences reviewable without gating CI.
- Do not change product behavior or claim mobile device emulation.

## Decisions

Use existing Python fixtures and installed Chrome with Playwright. Block non-fixture requests, freeze the browser clock and normalize the fixture inventory timestamp. Disable motion and wait for fonts and fixture readiness. Compare exact RGBA pixels and produce diff images and a JSON report. Keep local baselines in ignored `.local/` with environment metadata, since browser/font rendering varies by machine and browser version. Explicit baseline promotion prevents an ordinary capture from replacing evidence.

## Risks / Trade-offs

Exact pixels can differ across environments; metadata and report-only results make these differences visible for human review. Viewport-only mobile captures do not test mobile browser or touch behavior.

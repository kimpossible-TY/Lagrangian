# Design

## Completion criteria

The document title is the primary safe link, wraps without truncation, and is adjacent to its actual status and a separate alternatives trigger. At 360 and 390 CSS pixels the header contains a small brand and settings, followed by the title/count, full-width search, and compact document rows. Header minimum height is 64px; content maximum width is 880px with 20px gutters (16px below 480px); heading is 24px/650 and document titles 17px/650; rows have 16px vertical padding, a 44px minimum trigger, and 4px title/status spacing. At 320px, long names wrap; at wider sizes search shares the heading row. Short viewports scroll normally and the settings dialog scrolls within the viewport. Dark mode, zoom, empty, loading, error and no-results states retain contrast, meaning and focus. All controls have visible focus and 44px touch targets. No decorative preview or explanatory dashboard is introduced.

## Decisions

Keep Homepage inventory and account ownership. Use Basecoat precompiled styles for item, input and dialog patterns with existing shared theme tokens; use Web Awesome dropdown for alternatives. Pin and self-host the browser distribution and its transitive imports under explicit Homepage routes. Preserve keyed link nodes and open menu state across polls, restoring focus to the document section if a focused destination disappears. Native dialog continues to own modality and connection hash handling. Synthetic fixture serves the actual files without mutation endpoints.

## Risks

Browser rendering and keyboard interactions need independent Dogfood verification; source tests cannot establish visual quality or custom-element focus behavior.

# Design

## Completion criteria

The document title is the primary safe link, wraps without truncation, and is adjacent to its actual status and a separate alternatives trigger. At 360 and 390 CSS pixels the header contains a small brand and settings, followed by the title/count, full-width search, and compact document rows. Header minimum height is 64px; content maximum width is 880px with 20px gutters (16px below 480px); heading is 24px/650 and document titles 17px/650; rows have 16px vertical padding, a 44px minimum trigger, and 4px title/status spacing. At 320px, long names wrap; at wider sizes search shares the heading row. Short viewports scroll normally and the settings dialog scrolls within the viewport. Dark mode, zoom, empty, loading, error and no-results states retain contrast, meaning and focus. All controls have visible focus and 44px touch targets. No decorative preview or explanatory dashboard is introduced.

## Decisions

Keep Homepage inventory and account ownership. Use Basecoat precompiled Item and input styles with existing shared theme tokens; retain the existing native settings dialog and use Web Awesome dropdown for alternatives. This replaces the earlier native details decision in `simplify-homepage-library`. Pin and self-host the browser distribution and its transitive imports under explicit Homepage routes. Preserve keyed link nodes and open menu state across polls, restoring focus to the document section if a focused destination disappears. Web Awesome 3.14.0 resets roving state after show and asynchronous slot updates; a Home-owned compatibility bridge keeps the focused item and the component’s internal `active` property aligned, observing its public tabindex changes and synchronizing before keyboard handling. During opening, a single pending destination follows the latest user key, pointer or outside focus, while the component’s completion-time first-item focus does not replace that intent; removal or promotion updates its target. This version-specific dependency requires browser verification when upgrading. Native dialog continues to own modality and connection hash handling. Synthetic fixture serves the actual files without mutation endpoints.

## Risks

Browser rendering and keyboard interactions need independent Dogfood verification; source tests cannot establish visual quality or custom-element focus behavior.

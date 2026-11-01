## Context
The approved B prototype supplies the custom single-stroke path and 85% dimensions. The production inline SVG in web/index.html is the canonical geometry; reader.css fixes its 43.35 × 37.4px viewport.

## Decisions
ReaderActivityState and the shared ActivityNotice keep activity precedence, labels, errors and selection-release policy. An HTML-only StatusLogo observes the notice during refresh and adds a details disclosure in the toolbar. Ordinary busy notices yield to the logo; errors and held updates retain their existing visible notice/action. Ready means the current accepted document actually rendered. A bounded one-shot completion tint runs only after a busy-to-ready transition. Offline is a presentation derived from the accepted offline snapshot, never inferred from connection failure alone.

The logo uses the approved single continuous path for every layer. Light follows path length, starts slowly and accelerates toward the end, then returns gently. No horizontal gradient sweep. Reduced motion leaves stable color plus a visible badge/text alternative. Summary controls retain a 44px target. Native details gives keyboard and no-JavaScript access to status information; Escape/outside dismissal and listeners are owned/disposed by the HTML adapter.

Offline and highlight details retain their original IDs and writers when moved. Device diagnostics and explanations stay available under Advanced. No duplicated compiler or persistence state is introduced.

## Verification
Focused activity/appearance tests, HTML adapter browser interactions, reduced motion, mobile layout, reader lint, architecture and service/installation tests. Use isolated fixtures and do not restart/install user services.

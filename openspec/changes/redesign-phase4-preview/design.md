## Investigation

`scripts/builders.mjs` builds `tools/typst-preview-frontend` with Vite's single-file plugin; `scripts/stage-tinymist-assets.mjs` stages its output as `crates/tinymist-assets/src/typst-preview.html`, embedded by `include_str!`. The `-ng` workspace is not that build input. Registered `/p/<id>/` routes proxy the engine preview and inject the scoped bridge. The terminal Reader uses the HTML Reader and `reader.css` has no terminal-specific chrome rules.

## Decisions

Mirror theme tokens because the embedded preview is a separate bundle; a test checks the mirror. Keep page rendering untouched. Solid surfaces precede optional frosted chrome, with reduced-transparency, contrast and motion fallbacks. A static local fixture uses the real preview shell and styles with synthetic page content; it tests presentation, not the renderer or proxy. Slide mode retains its hidden-by-default 35px overlay, revealed by hover or focus; its controls retain 44px width but are constrained to that original height. Touch-only devices retain the prior visibility behavior. Explicit document themes scope the surround palette, preserving VS Code inline overrides. Captures cover hidden and focused toolbar states and forced themes. Browser review remains separate.

## Risks

CSS glass is a web approximation. Static contrast checks cannot establish contrast over every arbitrary backdrop or replace browser and device review.

## Context

The shared theme defines the Reader's existing palette and theme selection. The Homepage owns its presentation independently and must retain its DOM and behavior contracts.

## Goals / Non-Goals

- Add reusable color, spacing, type, radius, elevation, material, and motion roles in both themes.
- Restyle Homepage cards, controls, status, and responsive layout without changing Reader or chat visuals.
- Keep document reading surfaces solid and use glass only for Homepage card chrome.
- Do not introduce external fonts or JavaScript-driven animation.

## Decisions

Keep legacy palette declarations unchanged and alias new color roles to them. Supply theme-specific material values under both explicit dark and system-dark selectors. Homepage CSS starts with solid card surfaces and enhances them with backdrop blur only when supported; reduced transparency and increased contrast restore solid surfaces. Motion tokens become zero under reduced motion. The Homepage uses the requested system stack locally so shared Reader typography remains unchanged.

## Risks / Trade-offs

CSS backdrop blur is a frosted approximation, not native optical glass. Actual rendering, touch, contrast over content, and responsive geometry require browser and device review; the existing baseline harness provides follow-up visual evidence.

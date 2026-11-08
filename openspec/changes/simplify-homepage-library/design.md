# Design

## Context

The Homepage already owns inventory reconciliation and account controls. Its APIs and shared theme remain unchanged.

## Goals / Non-Goals

**Goals:** Keep stable safe document links, standard dialog behavior and existing account entry points.

**Non-Goals:** Change credentials, server behavior, other Reader interfaces or Dashboard itself.

## Decisions

Use a native modal dialog for settings and open it for the existing connection hash. This supplies modal keyboard and Escape behavior without a custom focus trap. Keep variant link nodes keyed across polls and reconcile their placement, selecting the first safe HTML then Paged destination. The later `adopt-home-ui-components` change supersedes the original native details presentation: the document title is the primary link and a dropdown presents alternatives while retaining destination identity.

## Risks / Trade-offs

[Changing a preferred destination can move a focused link] → Preserve its node where possible and restore focus to documents if removed. Browser and installed-layout checks remain PM-owned pending work.

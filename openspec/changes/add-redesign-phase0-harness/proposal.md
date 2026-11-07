## Why

A redesign needs a reproducible record of the existing Reader and Homepage UI and an early warning when supported DOM hooks disappear.

## What Changes

Add a selector contract, isolated browser fixture captures, report-only pixel comparison, and instructions for local baseline review.

## Capabilities

### New Capabilities

- `ui-regression-harness`: selector and visual regression evidence for the HTML Reader and Homepage.

### Modified Capabilities

None.

## Impact

Test tooling and local artifacts only. No product UI or runtime behavior changes.

## Non-goals

Redesign implementation, CI gating, physical-device coverage, and Rust changes.

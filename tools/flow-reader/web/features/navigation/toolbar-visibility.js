// Single-tap toolbar visibility: the reading surface yields its chrome on demand.
// Motion lives in CSS; this module owns the hidden state, tap disambiguation and
// the focus that an inert bar must not keep.

import { overlayOpen } from "./reading-navigation.js";

const TAP_MOVEMENT = 10;
const TAP_DURATION = 500;
const INTERACTIVE =
  'a[href], button, input, select, textarea, label, summary, [role="button"], [role="link"], ' +
  '[tabindex]:not([tabindex="-1"]), [contenteditable], .reader-toolbar';

/** Hides `.reader-toolbar` while the reader taps the document, and reveals it again. */
export function createToolbarVisibility({ toolbar, readingSurface }) {
  const owner = toolbar.ownerDocument;
  let hidden = false;
  let disposed = false;
  let pressed = null;
  let returnFocus = null;
  // True only while the bar is hidden because a tap hid it. A selection that
  // appears right after such a tap (double click, long press) takes the bar back.
  let tapHidden = false;
  const pointers = new Set();
  const listeners = new AbortController();
  const { signal } = listeners;

  const selectionCollapsed = () => owner.getSelection()?.isCollapsed !== false;
  const modified = (event) =>
    Boolean(event.metaKey || event.ctrlKey || event.shiftKey || event.altKey);
  const interactive = (target) => Boolean(target?.closest?.(INTERACTIVE));

  function hide() {
    if (hidden || disposed) return;
    hidden = true;
    // Focus must leave an inert, aria-hidden subtree; remember it so Escape can
    // return the reader to the control they came from.
    returnFocus = toolbar.contains(owner.activeElement) ? owner.activeElement : null;
    if (returnFocus) readingSurface.focus({ preventScroll: true });
    toolbar.setAttribute("inert", "");
    toolbar.setAttribute("aria-hidden", "true");
    toolbar.setAttribute("data-hidden", "true");
  }

  function reveal({ focus = false } = {}) {
    tapHidden = false;
    if (!hidden || disposed) return;
    hidden = false;
    const restore = returnFocus;
    returnFocus = null;
    toolbar.removeAttribute("data-hidden");
    toolbar.removeAttribute("aria-hidden");
    toolbar.removeAttribute("inert");
    if (focus && restore && toolbar.contains(restore)) restore.focus({ preventScroll: true });
  }

  function toggle() {
    if (hidden) reveal();
    else hide();
  }

  // Only the tap path records that it hid the bar; a public `hide()` must not.
  function toggleFromTap() {
    if (!hidden) tapHidden = true;
    toggle();
  }

  function onPointerDown(event) {
    // Never let a release that produced no click leak into the next gesture.
    if (pointers.size === 0) pressed = null;
    pointers.add(event.pointerId);
    if (pointers.size > 1) {
      // A second finger turns the gesture into something other than a tap.
      pressed = null;
      return;
    }
    if (
      !event.isPrimary ||
      event.button !== 0 ||
      modified(event) ||
      event.defaultPrevented ||
      interactive(event.target) ||
      // A gesture that starts on a selection is not a toolbar tap; it is the
      // reader dismissing, extending or double-clicking a selection.
      !selectionCollapsed() ||
      // A tap that dismisses an overlay or a dialog should not fold the bar away.
      overlayOpen(owner)
    )
      return;
    pressed = { id: event.pointerId, x: event.clientX, y: event.clientY, time: event.timeStamp };
  }

  function onPointerMove(event) {
    if (pressed?.id !== event.pointerId) return;
    if (Math.hypot(event.clientX - pressed.x, event.clientY - pressed.y) > TAP_MOVEMENT)
      pressed.moved = true;
  }

  function onPointerUp(event) {
    pointers.delete(event.pointerId);
    const start = pressed;
    if (!start || start.id !== event.pointerId) return;
    if (start.moved || event.timeStamp - start.time > TAP_DURATION) pressed = null;
    else start.released = true;
  }

  function onPointerCancel(event) {
    pointers.delete(event.pointerId);
    if (pointers.size === 0) pressed = null;
  }

  function onClick(event) {
    const start = pressed;
    pressed = null;
    pointers.clear();
    // The click is the commit point, because application handlers that consume
    // a tap have already called preventDefault by now.
    if (
      !start?.released ||
      event.button !== 0 ||
      modified(event) ||
      event.defaultPrevented ||
      !selectionCollapsed() ||
      interactive(event.target) ||
      !readingSurface.contains(event.target)
    )
      return;
    // A tap can begin a text selection that settles after the click; confirm on
    // the microtask and on the next frame before the bar moves.
    queueMicrotask(() => {
      if (disposed || !selectionCollapsed()) return;
      requestAnimationFrame(() => {
        if (!disposed && selectionCollapsed()) toggleFromTap();
      });
    });
  }

  function onDoubleClick() {
    // The first click of a double click hid the bar; the second one selects a
    // word. Give the bar back instead of leaving it stuck out of reach.
    if (tapHidden) reveal();
  }

  function onSelectionChange() {
    if (tapHidden && !selectionCollapsed()) reveal();
  }

  function onKeyDown(event) {
    if (event.key !== "Escape" || !hidden) return;
    // The same Escape may dismiss an overlay; the bar returns with it.
    reveal({ focus: true });
  }

  function onRelease(event) {
    pointers.delete(event.pointerId);
  }

  readingSurface.addEventListener("pointerdown", onPointerDown, { signal });
  readingSurface.addEventListener("pointermove", onPointerMove, { signal, passive: true });
  readingSurface.addEventListener("pointerup", onPointerUp, { signal });
  readingSurface.addEventListener("pointercancel", onPointerCancel, { signal });
  readingSurface.addEventListener("click", onClick, { signal });
  readingSurface.addEventListener("dblclick", onDoubleClick, { signal });
  // A release outside the surface never reaches the local handler; without this
  // cleanup a missed one would keep the pointer count above one for good.
  owner.addEventListener("pointerup", onRelease, { signal });
  owner.addEventListener("pointercancel", onRelease, { signal });
  // The bar may be hidden while a selection settles without a pointer event,
  // for example a keyboard or programmatic selection.
  owner.addEventListener("selectionchange", onSelectionChange, { signal });
  // Defensive: a script or restored focus can reach the bar despite inert.
  toolbar.addEventListener("focusin", () => reveal(), { signal });
  owner.addEventListener("keydown", onKeyDown, { signal });

  return {
    reveal,
    hide,
    toggle,
    get hidden() {
      return hidden;
    },
    dispose() {
      if (disposed) return;
      reveal();
      disposed = true;
      pointers.clear();
      pressed = null;
      listeners.abort();
    },
  };
}

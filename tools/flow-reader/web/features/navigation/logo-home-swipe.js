/** Pure single-pointer swipe state. Coordinates are in CSS pixels. */
export function logoSwipe(state, event) {
  if (event.type === "down") {
    if (state) return { ...state, cancelled: true };
    if (!event.isPrimary || event.button !== 0) return null;
    return { id: event.pointerId, x: event.x, y: event.y, width: event.width, cancelled: false };
  }
  if (!state || event.pointerId !== state.id) return state;
  if (event.type === "cancel") return { ...state, cancelled: true };
  const dx = event.x - state.x;
  const dy = event.y - state.y;
  const cancelled = state.cancelled || dx < -10 || (Math.abs(dy) > 10 && Math.abs(dx) <= 2 * Math.abs(dy));
  return { ...state, dx, dy, cancelled, complete: event.type === "up" && !cancelled && dx >= Math.min(60, 0.4 * state.width) && Math.abs(dx) > 2 * Math.abs(dy) };
}

/** Shared Reader routes are the only HTML Reader routes with a Homepage. */
export function logoHomeURL(pathname) {
  return /^\/d\/[^/]+\//.test(pathname) ? "/" : null;
}

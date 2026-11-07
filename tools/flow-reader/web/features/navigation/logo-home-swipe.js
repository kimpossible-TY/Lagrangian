/** Single-pointer gesture classifier; effects and timers belong to the adapter. */
export function logoGesture(state, event) {
  if (event.type === "down") {
    if (state && state.phase !== "done") return { ...state, phase: "done" };
    if (!event.isPrimary || event.button !== 0) return null;
    return { phase: "pressing", id: event.pointerId, x: event.x, y: event.y, width: event.width };
  }
  if (!state || (event.pointerId !== undefined && event.pointerId !== state.id)) return state;
  if (event.type === "hold") return state.phase === "pressing" ? { ...state, phase: "longpress-fired", action: "home" } : state;
  if (event.type === "cancel") return { ...state, phase: "done", action: null };
  if (state.phase === "longpress-fired" || state.phase === "done") return { ...state, action: null, phase: event.type === "up" ? "done" : state.phase };
  const dx = event.x - state.x;
  const dy = event.y - state.y;
  let phase = state.phase;
  if (Math.hypot(dx, dy) > 10 && phase === "pressing") phase = "swiping";
  const cancelled = state.cancelled || dx < -10 || (Math.abs(dy) > 10 && Math.abs(dx) <= 2 * Math.abs(dy));
  const complete = event.type === "up" && !cancelled && dx >= Math.min(60, 0.4 * state.width) && Math.abs(dx) > 2 * Math.abs(dy);
  return { ...state, dx, dy, cancelled, phase: event.type === "up" ? "done" : phase, action: complete ? "home" : null };
}

/** Shared Reader routes are the only HTML Reader routes with a Homepage. */
export function logoHomeURL(pathname) {
  return /^\/d\/[^/]+\//.test(pathname) ? "/" : null;
}

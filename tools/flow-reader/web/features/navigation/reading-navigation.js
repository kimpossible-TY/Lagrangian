// Reading gestures own horizontal drawer movement and two-finger text sizing.
// One-finger vertical scrolling stays with the browser.
const clamp = (value, low, high) => Math.max(low, Math.min(high, value));

export function pinchFont(size, distance, initial) {
  if (!(initial >= 24) || !Number.isFinite(distance)) return size;
  const ratio = distance / initial;
  return Math.abs(ratio - 1) < 0.04 ? size : clamp(Math.round(size * ratio), 13, 30);
}

export function springState(from, to, velocity, seconds) {
  // Locally tuned critical damping, in CSS pixels and seconds.
  const frequency = 30;
  const displacement = from - to;
  const coefficient = velocity + frequency * displacement;
  const decay = Math.exp(-frequency * seconds);
  return {
    position: to + (displacement + coefficient * seconds) * decay,
    velocity: (velocity - frequency * coefficient * seconds) * decay,
  };
}

// A small anticipation before outside-tap dismissal; gestures keep their momentum.
export function drawerMotionState(motion, seconds) {
  const { from, to, velocity, playful } = motion;
  if (!playful) return springState(from, to, velocity, seconds);
  const anticipation = 0.08;
  if (seconds < anticipation) {
    const phase = (Math.PI * seconds) / anticipation;
    return {
      position: from + 4 * (1 - Math.cos(phase)),
      velocity: ((4 * Math.PI) / anticipation) * Math.sin(phase),
    };
  }
  return springState(from + 8, to, 0, seconds - anticipation);
}

export class SwipeTracker {
  constructor({ x, y, time, open, width, offset = open ? 0 : -width }) {
    Object.assign(this, { x, y, open, width, offset });
    this.samples = [{ x, time }];
    this.intent = "pending";
    this.delta = 0;
  }

  move(x, y, time) {
    this.delta = x - this.x;
    const vertical = Math.abs(y - this.y);
    if (this.intent === "pending" && Math.max(Math.abs(this.delta), vertical) >= 6) {
      this.intent =
        vertical > Math.abs(this.delta) * 0.65 || (this.open ? this.delta > 0 : this.delta < 0)
          ? "rejected"
          : "horizontal";
    }
    this.samples.push({ x, time });
    this.samples = this.samples.filter((sample) => sample.time >= time - 100).slice(-12);
    return this.intent;
  }

  release(x, y, time, canceled = false) {
    this.move(x, y, time);
    const first = this.samples[0];
    const elapsed = time - first.time;
    const velocity = elapsed > 0 ? clamp(((x - first.x) * 1000) / elapsed, -3000, 3000) : 0;
    const progress = clamp(1 + (this.offset + this.delta) / this.width, 0, 1);
    let open = this.open;
    if (!canceled && this.intent === "horizontal") {
      if (velocity > 500 && (this.open || this.delta > 24)) open = true;
      else if (velocity < -500 && (!this.open || this.delta < -24)) open = false;
      else open = progress >= (this.open ? 0.55 : 0.45);
    }
    return { open, velocity: canceled ? 0 : velocity };
  }
}

export class OutlineDrawer {
  constructor(
    dialog,
    trigger,
    { reducedMotion = matchMedia("(prefers-reduced-motion: reduce)"), beforeOpen = () => {} } = {},
  ) {
    this.dialog = dialog;
    this.trigger = trigger;
    this.panel = dialog.querySelector(".reader-drawer-panel");
    this.scrim = dialog.querySelector(".reader-drawer-scrim");
    // Keep presentation alive without relying on a closed dialog's display/overlay
    // transitions. This also previews a swipe without native dialog autofocus.
    this.visual = document.createElement("div");
    this.visual.className = "reader-navigation-visual";
    this.visual.hidden = true;
    this.visual.inert = true;
    this.visual.setAttribute("aria-hidden", "true");
    document.body.append(this.visual);
    this.reduced = reducedMotion;
    this.beforeOpen = beforeOpen;
    this.travel = Math.min(352, document.documentElement.clientWidth - 32) + 40;
    this.position = -this.travel;
    this.target = false;
    this.sequence = 0;
    trigger.addEventListener("click", () => (this.target ? this.close() : this.open()));
    dialog.querySelector("#reader-navigation-close").addEventListener("click", () => this.close());
    dialog.addEventListener("cancel", (event) => {
      event.preventDefault();
      this.close();
    });
    dialog.addEventListener("click", (event) => {
      if (event.target === dialog) this.settle(false, undefined, true);
    });
    dialog.addEventListener("close", () => {
      if (!dialog.open) trigger.setAttribute("aria-expanded", "false");
    });
    this.reduced.addEventListener("change", () => {
      this.stop();
      this.paint(this.target ? 0 : -this.travel);
      if (!this.target) this.hideVisual();
    });
    let viewportWidth = document.documentElement.clientWidth;
    window.addEventListener("resize", () => {
      const nextWidth = document.documentElement.clientWidth;
      const widthChanged = nextWidth !== viewportWidth;
      viewportWidth = nextWidth;
      if (!widthChanged || (!dialog.open && this.visual.hidden)) return;
      this.stop();
      this.travel = this.measureTravel();
      this.paint(this.target ? 0 : -this.travel);
      if (!this.target) this.hideVisual();
    });
  }

  measureTravel() {
    // Clear the floating inset and shadow as well as the capsule itself.
    return this.panel.offsetWidth + Math.max(0, this.panel.offsetLeft) + 24;
  }

  paint(position) {
    this.position = clamp(position, -this.travel, 8);
    this.panel.style.transform = `translateX(${this.position}px)`;
    this.scrim.style.opacity = clamp(1 + this.position / this.travel, 0, 1);
  }

  stop() {
    let velocity = 0;
    if (this.motion) {
      const state = drawerMotionState(
        this.motion,
        Math.max(0, Number(this.animation.currentTime) || 0) / 1000,
      );
      this.paint(state.position);
      velocity = state.velocity;
      this.animation.cancel();
      this.scrimAnimation.cancel();
      this.motion = null;
    }
    this.sequence++;
    return velocity;
  }

  hideVisual() {
    this.visual.hidden = true;
    this.dialog.append(this.scrim, this.panel);
  }

  prepare(modal) {
    const readingX = window.scrollX;
    const readingY = window.scrollY;
    const wasHidden = !this.dialog.open && this.visual.hidden;
    if (modal) {
      this.hideVisual();
      if (!this.dialog.open) this.dialog.showModal();
    } else {
      this.visual.append(this.scrim, this.panel);
      this.visual.hidden = false;
    }
    this.dialog.toggleAttribute("data-modal", modal);
    const oldTravel = this.travel;
    this.travel = this.measureTravel();
    if (wasHidden && !this.motion && this.position <= -oldTravel) this.paint(-this.travel);
    this.trigger.setAttribute("aria-expanded", String(modal));
    if (window.scrollX !== readingX || window.scrollY !== readingY)
      window.scrollTo(readingX, readingY);
    if (modal) this.beforeOpen();
  }

  settle(open, velocity, playful = false) {
    const inherited = this.stop();
    this.target = open;
    if (open) this.prepare(true);
    else {
      this.dialog.close();
      this.visual.append(this.scrim, this.panel);
      this.visual.hidden = false;
      this.dialog.removeAttribute("data-modal");
      this.trigger.setAttribute("aria-expanded", "false");
    }
    const to = open ? 0 : -this.travel;
    if (this.reduced.matches || !this.panel.animate) {
      this.paint(to);
      if (!open) this.hideVisual();
      return;
    }
    const from = this.position;
    const speed = velocity ?? inherited;
    // Anticipate only from rest; interrupting an entry preserves its velocity.
    playful = playful && Math.abs(from) < 0.5 && Math.abs(speed) < 10;
    const duration = playful ? 400 : 320;
    const motion = { from, to, velocity: speed, playful };
    const frames = [],
      scrim = [];
    for (let frame = 0; frame <= 40; frame++) {
      const offset = frame / 40;
      const position =
        frame === 40
          ? to
          : clamp(drawerMotionState(motion, (offset * duration) / 1000).position, -this.travel, 8);
      frames.push({ transform: `translateX(${position}px)`, offset });
      scrim.push({ opacity: clamp(1 + position / this.travel, 0, 1), offset });
    }
    const sequence = this.sequence;
    this.motion = motion;
    const timing = { duration, easing: "linear", fill: "forwards" };
    this.animation = this.panel.animate(frames, timing);
    this.scrimAnimation = this.scrim.animate(scrim, timing);
    this.animation.onfinish = () => {
      if (sequence !== this.sequence) return;
      this.paint(to);
      this.animation.cancel();
      this.scrimAnimation.cancel();
      this.motion = null;
      if (!this.target) this.hideVisual();
    };
  }

  open() {
    this.settle(true);
  }
  close() {
    this.settle(false);
  }

  beginDrag() {
    this.stop();
    if (!this.dialog.open) this.prepare(false);
    this.grab = this.position;
    return { width: this.travel, offset: this.grab };
  }

  drag(delta) {
    if (!this.reduced.matches) this.paint(this.grab + delta);
  }
}

const interactive = "a,button,input,select,textarea,[contenteditable]";
const point = (touch) => ({ x: touch.clientX, y: touch.clientY });
const distance = (touches) =>
  Math.hypot(touches[1].clientX - touches[0].clientX, touches[1].clientY - touches[0].clientY);

export class ReaderGestures {
  constructor(article, drawer, { getFont, setFont, previewFont, cancelFont, preview, announce }) {
    Object.assign(this, {
      article,
      drawer,
      getFont,
      setFont,
      previewFont,
      cancelFont,
      preview,
      announce,
    });
    this.state = null;
    this.waiting = false;
    this.listeners = new AbortController();
    const { signal } = this.listeners;
    article.dataset.readerGestures = "true";
    for (const root of [article, drawer.dialog]) {
      root.addEventListener("touchstart", (event) => this.start(event), { passive: false, signal });
      root.addEventListener("touchmove", (event) => this.move(event), { passive: false, signal });
      root.addEventListener("touchend", (event) => this.end(event), { passive: false, signal });
      root.addEventListener("touchcancel", (event) => this.end(event, true), {
        passive: false,
        signal,
      });
    }
    for (const name of ["gesturestart", "gesturechange", "gestureend"]) {
      article.addEventListener(
        name,
        (event) => {
          if (event.cancelable) event.preventDefault();
        },
        { passive: false, signal },
      );
    }
    window.addEventListener("blur", () => this.cancel(), { signal });
    window.addEventListener("pagehide", () => this.cancel(), { signal });
    document.addEventListener(
      "visibilitychange",
      () => {
        if (document.hidden) this.cancel();
      },
      { signal },
    );
    let viewportWidth = document.documentElement.clientWidth;
    window.addEventListener(
      "resize",
      () => {
        const nextWidth = document.documentElement.clientWidth;
        if (nextWidth !== viewportWidth) this.cancel();
        viewportWidth = nextWidth;
      },
      { signal },
    );
  }

  get active() {
    return this.state?.kind === "pinch" || Boolean(this.state?.owned);
  }

  selected() {
    return !window.getSelection()?.isCollapsed;
  }

  overlayOpen() {
    return (
      document.querySelector("dialog[open], [data-fallback]:not([hidden])") ||
      (typeof this.article.showPopover === "function" &&
        document.querySelector("[popover]:popover-open"))
    );
  }

  start(event) {
    const touches = [...event.touches];
    if (this.waiting) return;
    if (touches.length > 2) {
      this.cancel();
      this.waiting = true;
      return;
    }
    const onArticle = this.article.contains(event.target);
    if (touches.length === 2) {
      if (
        this.state?.owned ||
        !onArticle ||
        this.selected() ||
        this.overlayOpen() ||
        touches.some((touch) => touch.target && !this.article.contains(touch.target))
      ) {
        this.cancel();
        this.waiting = true;
        return;
      }
      const initial = distance(touches);
      if (initial < 24) {
        this.state = null;
        return;
      }
      this.state = {
        kind: "pinch",
        ids: touches.map((touch) => touch.identifier),
        initial,
        size: this.getFont(),
        candidate: this.getFont(),
      };
      if (event.cancelable) event.preventDefault();
      return;
    }
    if (touches.length !== 1 || this.selected()) return;
    const open = this.drawer.dialog.open && this.drawer.target;
    if (event.target.closest(open ? "button,input,select,textarea,[contenteditable]" : interactive))
      return;
    const touch = touches[0];
    // Swiping from the middle of the passage is discoverable too; reserve only
    // the outer browser-navigation edges and normal interactive targets.
    if (onArticle && (touch.clientX < 24 || touch.clientX > innerWidth - 24)) return;
    if (!onArticle && (!open || !this.drawer.panel.contains(event.target))) return;
    if (onArticle && this.overlayOpen()) return;
    const start = point(touch);
    this.state = {
      kind: "swipe",
      id: touch.identifier,
      owned: false,
      tracker: new SwipeTracker({
        ...start,
        time: event.timeStamp,
        open,
        width: this.drawer.travel,
      }),
    };
  }

  move(event) {
    const state = this.state;
    if (!state) return;
    const touches = [...event.touches];
    if (this.selected()) {
      this.cancel();
      this.waiting = touches.length > 0;
      return;
    }
    if (state.kind === "pinch") {
      if (
        touches.length !== 2 ||
        touches.some((touch) => !state.ids.includes(touch.identifier)) ||
        this.selected()
      ) {
        this.cancel();
        this.waiting = touches.length > 0;
        return;
      }
      if (event.cancelable) event.preventDefault();
      state.candidate = pinchFont(state.size, distance(touches), state.initial);
      if (this.pinchFrame === undefined) {
        this.pinchFrame = requestAnimationFrame(() => {
          if (this.state !== state) return;
          this.pinchFrame = undefined;
          if (this.selected() || this.overlayOpen()) {
            this.cancel();
            return;
          }
          if (state.candidate !== this.getFont()) {
            this.previewFont?.(state.candidate);
            state.previewed = true;
          }
          this.preview.querySelector("output").value = `${state.candidate}px`;
          this.preview.style.setProperty("--pinch-size", `${state.candidate}px`);
          this.preview.hidden = false;
        });
      }
      return;
    }
    if (touches.length !== 1) {
      this.cancel();
      this.waiting = true;
      return;
    }
    const touch = touches.find((item) => item.identifier === state.id);
    if (!touch) return;
    const intent = state.tracker.move(touch.clientX, touch.clientY, event.timeStamp);
    if (intent !== "horizontal") {
      if (intent === "rejected") this.state = null;
      return;
    }
    if (!state.owned) {
      const geometry = this.drawer.beginDrag();
      Object.assign(state.tracker, geometry);
      state.owned = true;
    }
    if (event.cancelable) event.preventDefault();
    this.drawer.drag(state.tracker.delta);
  }

  end(event, canceled = false) {
    const state = this.state;
    if (state?.kind === "pinch" && event.touches.length < 2) {
      this.state = null;
      this.cancelPinchFrame();
      this.preview.hidden = true;
      if (event.cancelable) event.preventDefault();
      if (
        !canceled &&
        !this.selected() &&
        !this.overlayOpen() &&
        (state.candidate !== state.size || state.previewed)
      ) {
        this.setFont(state.candidate);
        this.announce.textContent = `글자 크기 ${state.candidate}픽셀`;
      } else this.cancelFont?.();
      this.waiting = event.touches.length > 0;
    } else if (state?.kind === "swipe") {
      const touch = [...event.changedTouches].find((item) => item.identifier === state.id);
      if (touch && state.owned) {
        if (event.cancelable) event.preventDefault();
        const result = state.tracker.release(
          touch.clientX,
          touch.clientY,
          event.timeStamp,
          canceled,
        );
        this.drawer.settle(result.open, result.velocity);
      }
      this.state = null;
    }
    if (event.touches.length === 0) this.waiting = false;
    if (canceled) this.cancel();
  }

  cancel() {
    if (this.state?.owned) this.drawer.settle(this.state.tracker.open, 0);
    const pinching = this.state?.kind === "pinch";
    this.state = null;
    this.cancelPinchFrame();
    this.preview.hidden = true;
    if (pinching) {
      this.waiting = true;
      this.cancelFont?.();
    }
  }

  cancelPinchFrame() {
    if (this.pinchFrame !== undefined) cancelAnimationFrame(this.pinchFrame);
    this.pinchFrame = undefined;
  }

  dispose() {
    this.cancel();
    this.listeners.abort();
  }
}

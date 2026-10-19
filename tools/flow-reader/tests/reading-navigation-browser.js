// Synthetic touch wiring checks; native device gesture arbitration is a separate check.
import { OutlineDrawer, ReaderGestures, readingSettings } from "/reading-navigation.js";
import { logicalTextIndex } from "/math-identity.js";

const report = { checks: [], errors: [] };
const output = document.createElement("script");
output.type = "application/json";
output.id = "reading-navigation-report";
document.body.append(output);
function check(name, condition) {
  report.checks.push(name);
  if (!condition) report.errors.push(name);
  output.textContent = JSON.stringify(report);
}
async function until(condition, name) {
  const deadline = performance.now() + 20000;
  while (!condition()) {
    if (performance.now() > deadline) throw new Error(name);
    await new Promise((resolve) => setTimeout(resolve, 50));
  }
}
const pause = (ms = 350) => new Promise((resolve) => setTimeout(resolve, ms));
const article = document.querySelector("#reader-document");
const drawer = document.querySelector("#reader-navigation");
const panel = drawer.querySelector(".reader-drawer-panel");
const font = () => Number(document.querySelector("#reader-size").value);
const target = () => article.querySelector("p") ?? article;
// Operational notices can appear during an asynchronous mathematical repaint.
// Compare authored passage characters rather than those status announcements.
function authoredText() {
  const index = logicalTextIndex(article);
  return index.text
    .split("")
    .filter((_, at) => !index.points[at]?.start[0].parentElement?.closest('[role="status"]'))
    .join("")
    .replace(/\s+/g, " ")
    .trim();
}
let clock = 0;
function touch(id, x, y, node = target()) {
  const contact = { identifier: id, target: node, clientX: x, clientY: y, pageX: x, pageY: y };
  return typeof Touch === "function" ? new Touch(contact) : contact;
}
function send(
  name,
  touches,
  changed = touches,
  node = changed[0]?.target ?? target(),
  elapsed = 30,
) {
  clock += elapsed;
  const init = {
    touches,
    changedTouches: changed,
    targetTouches: touches,
    bubbles: true,
    cancelable: true,
  };
  const event =
    typeof TouchEvent === "function" ? new TouchEvent(name, init) : new Event(name, init);
  if (typeof TouchEvent !== "function") {
    for (const key of ["touches", "changedTouches", "targetTouches"])
      Object.defineProperty(event, key, { value: init[key] });
  }
  Object.defineProperty(event, "timeStamp", { value: clock });
  node.dispatchEvent(event);
  return event.defaultPrevented;
}
function pinch(ratio) {
  const a = touch(1, 80, 250),
    b = touch(2, 180, 250),
    c = touch(2, 80 + ratio * 100, 250);
  send("touchstart", [a, b]);
  send("touchmove", [a, c]);
  return { a, b: c };
}
function finish({ a, b }, canceled = false) {
  send(canceled ? "touchcancel" : "touchend", [a], [b]);
  send("touchend", [], [a]);
}
function swipe(start, end, node = target(), canceled = false) {
  const a = touch(3, start[0], start[1], node),
    b = touch(3, end[0], end[1], node);
  send("touchstart", [a]);
  const owned = send("touchmove", [b]);
  send(canceled ? "touchcancel" : "touchend", [], [b]);
  return owned;
}

async function run() {
  await until(
    () =>
      article.querySelector("[data-reader-key]") &&
      !article.getAttribute("aria-busy").includes("true"),
    "Reader ready",
  );
  await document.fonts.ready;
  await pause();
  const original = font();
  const canonical = authoredText();
  const scrollSpace = document.createElement("div");
  scrollSpace.style.height = "150vh";
  scrollSpace.setAttribute("aria-hidden", "true");
  document.body.append(scrollSpace);
  check(
    "Toolbar exposes exactly two action icons",
    document.querySelectorAll(".reader-toolbar button").length > 2 &&
      [...document.querySelectorAll(".reader-toolbar button")].filter(
        (n) => n.getBoundingClientRect().height > 1,
      ).length === 2,
  );
  check(
    "Article owns pinch while retaining vertical pan",
    getComputedStyle(article).touchAction === "pan-y",
  );

  const growth = pinch(1.4);
  check(
    "Pinch previews a candidate without reflowing during movement",
    font() === original && !document.querySelector("#reader-font-preview").hidden,
  );
  finish(growth);
  const larger = Math.min(30, Math.round(original * 1.4));
  check(
    "Release commits the chosen text size",
    font() === larger && getComputedStyle(article).fontSize === `${larger}px`,
  );
  const restore = pinch(original / font());
  finish(restore);
  check("Reverse pinch restores the selected text size", font() === original);

  const canceled = pinch(1.8);
  finish(canceled, true);
  check(
    "Touch cancellation discards font changes and hides feedback",
    font() === original && document.querySelector("#reader-font-preview").hidden,
  );
  const extra = pinch(1.8),
    third = touch(4, 120, 300);
  send("touchstart", [extra.a, extra.b, third], [third]);
  send("touchend", [extra.a, extra.b], [third]);
  send("touchmove", [extra.a, extra.b]);
  finish(extra);
  check("A third finger cancels without restarting on remaining contacts", font() === original);

  const text = target().firstChild;
  if (text?.nodeType === Node.TEXT_NODE) {
    const range = document.createRange();
    range.selectNodeContents(text);
    getSelection().removeAllRanges();
    getSelection().addRange(range);
    finish(pinch(1.8));
    swipe([48, 300], [260, 302]);
    check(
      "A selected passage blocks font and drawer gestures",
      font() === original && !drawer.open && !getSelection().isCollapsed,
    );
    getSelection().removeAllRanges();
  }
  const vertical = swipe([48, 300], [52, 390]);
  check("Vertical reading motion is not canceled", !vertical && !drawer.open);
  swipe([5, 300], [250, 301]);
  check("The outer browser edge does not trigger the drawer", !drawer.open);
  const link = article.querySelector("a");
  if (link) {
    swipe([48, 300], [260, 301], link);
    check("Reference/link starts retain their normal action", !drawer.open);
  }
  swipe([120, 300], [240, 301]);
  check("A rightward swipe from the passage center opens the outline", drawer.open);
  document.querySelector("#reader-navigation-close").click();
  await pause();
  swipe([48, 300], [260, 302], target(), true);
  check("A canceled opening swipe remains closed", !drawer.open);
  await pause();
  const a = touch(3, 48, 300),
    b = touch(3, 260, 302);
  window.scrollTo(0, 240);
  const beforeOutlineScroll = scrollY;
  send("touchstart", [a]);
  send("touchmove", [b]);
  check(
    "The drawer follows an owned swipe before committing modality",
    !drawer.open &&
      panel.parentElement.classList.contains("reader-navigation-visual") &&
      panel.getBoundingClientRect().left > -panel.getBoundingClientRect().width,
  );
  send("touchend", [], [b]);
  check("A completed opening swipe becomes a native modal", drawer.matches(":modal"));
  check(
    "Opening the capsule preserves the article position",
    beforeOutlineScroll > 0 && Math.abs(scrollY - beforeOutlineScroll) < 1,
  );
  check(
    "The outline marks the current reading location",
    drawer.querySelectorAll('[aria-current="location"]').length === 1,
  );
  await pause();
  check(
    "The settled capsule retains the scrolled passage",
    Math.abs(scrollY - beforeOutlineScroll) < 1,
  );
  swipe([240, 300], [25, 302], panel, true);
  check("A canceled closing swipe keeps the outline open", drawer.open);
  await pause();
  swipe([240, 300], [25, 302], panel);
  check("Reverse swipe closes the modal immediately", !drawer.open);
  document.querySelector("#reader-menu").click();
  await pause();
  check(
    "Rapid reopening survives the previous exit animation",
    drawer.matches(":modal") && Math.abs(panel.getBoundingClientRect().left - panel.offsetLeft) < 1,
  );
  const capsule = panel.getBoundingClientRect();
  check(
    "The outline floats inside every viewport edge with a rounded surface",
    capsule.left >= 12 &&
      capsule.top >= 12 &&
      capsule.right <= document.documentElement.clientWidth - 11 &&
      capsule.bottom <= innerHeight - 12 &&
      parseFloat(getComputedStyle(panel).borderRadius) >= 24,
  );
  document.querySelector("#reader-navigation-close").click();

  document.querySelector("#reader-appearance-open").click();
  // Measure the resting target after its opening scale transition.
  await pause(200);
  report.settings = {
    open: document.querySelector("#reader-appearance-panel").matches(":popover-open"),
    width: document.querySelector("#reader-larger").getBoundingClientRect().width,
  };
  check(
    "Settings contains the font controls",
    document.querySelector("#reader-appearance-panel").matches(":popover-open") &&
      Math.round(document.querySelector("#reader-larger").getBoundingClientRect().width) >= 44,
  );
  const plus = document.querySelector("#reader-larger");
  if (!plus.disabled) {
    plus.click();
    document.querySelector("#reader-smaller").click();
  }
  check("Semantic font buttons remain an alternative", font() === original);
  check(
    "Reading settings no longer expose a local quotation library",
    !document.querySelector("#reader-highlights-open, #reader-highlights"),
  );

  const fallbackPanel = document.querySelector("#reader-appearance-panel").cloneNode(true);
  const fallbackTrigger = document.createElement("button");
  fallbackPanel.id = "fallback-settings-fixture";
  fallbackPanel.hidden = true;
  fallbackPanel.hidePopover = undefined;
  fallbackPanel.querySelector("select").hidden = false;
  for (const radio of fallbackPanel.querySelectorAll("input[name]")) radio.removeAttribute("name");
  fallbackPanel.querySelector(".reader-appearance-close").removeAttribute("popovertarget");
  for (const node of fallbackPanel.querySelectorAll("[id]")) node.removeAttribute("id");
  document.body.append(fallbackPanel, fallbackTrigger);
  readingSettings(fallbackPanel, fallbackTrigger);
  fallbackTrigger.click();
  check(
    "Unsupported popovers retain dismissible settings and font actions",
    !fallbackPanel.hidden &&
      fallbackPanel.dataset.fallback === "true" &&
      !fallbackPanel.hasAttribute("popover") &&
      fallbackPanel.querySelectorAll(".reader-type-controls button").length === 2 &&
      fallbackPanel.contains(document.activeElement) &&
      fallbackPanel.style.maxHeight !== "",
  );
  fallbackPanel.querySelector(".reader-appearance-close").click();
  check(
    "Fallback dismissal restores its trigger",
    fallbackPanel.hidden && document.activeElement === fallbackTrigger,
  );
  fallbackPanel.remove();
  fallbackTrigger.remove();

  await pause(450);
  const fixture = drawer.cloneNode(true),
    trigger = document.createElement("button");
  fixture.id = "motion-fixture";
  fixture.style.cssText =
    "position:fixed;inset:0;width:100%;height:100%;max-width:none;max-height:none;opacity:0;pointer-events:none";
  fixture.querySelector(".reader-drawer-panel").style.transform = "translateX(-352px)";
  document.body.append(fixture, trigger);
  const preference = new EventTarget();
  preference.matches = false;
  const motion = new OutlineDrawer(fixture, trigger, { reducedMotion: preference });
  motion.open();
  await pause();
  fixture.dispatchEvent(new MouseEvent("click", { bubbles: true }));
  check(
    "Dismissal commits immediately but retains an inert visible presentation",
    !fixture.open &&
      !motion.visual.hidden &&
      motion.visual.inert &&
      motion.visual.getAttribute("aria-hidden") === "true" &&
      motion.panel.parentElement === motion.visual &&
      getComputedStyle(motion.panel).display !== "none",
  );
  await pause(65);
  check(
    "Outside dismissal has a visible anticipation",
    motion.panel.getBoundingClientRect().left > motion.panel.offsetLeft + 3,
  );
  motion.open();
  await pause();
  check(
    "Reopening cancels the exit presentation without losing the modal",
    fixture.open && motion.visual.hidden && motion.panel.parentElement === fixture,
  );
  motion.open();
  preference.matches = true;
  preference.dispatchEvent(new Event("change"));
  check(
    "Changing reduced motion cancels the active spring",
    !motion.motion && motion.position === 0,
  );
  const floatingRight = fixture.querySelector(".reader-drawer-panel").getBoundingClientRect().right;
  motion.close();
  check("Reduced motion closes without a remaining animation", !fixture.open && !motion.motion);
  check(
    "Closing travel clears the floating capsule and its shadow",
    floatingRight + motion.position < -12,
  );
  const gestureArticle = document.createElement("main");
  document.body.append(gestureArticle);
  new ReaderGestures(gestureArticle, motion, {
    getFont: () => 13,
    setFont: () => {},
    preview: document.querySelector("#reader-font-preview"),
    announce: document.querySelector("#reader-gesture-message"),
  });
  swipe([120, 300], [240, 302], gestureArticle);
  check(
    "Reduced motion retains swipe-to-open functionality",
    fixture.open && motion.target && !motion.motion && motion.position === 0,
  );
  motion.close();
  check("Reduced motion leaves no visible exit layer", motion.visual.hidden);
  gestureArticle.remove();
  motion.visual.remove();
  fixture.remove();
  trigger.remove();
  await pause();
  const finalText = authoredText();
  if (finalText !== canonical) {
    let at = 0;
    while (at < canonical.length && canonical[at] === finalText[at]) at++;
    report.textDifference = {
      at,
      before: canonical.slice(Math.max(0, at - 20), at + 80),
      after: finalText.slice(Math.max(0, at - 20), at + 80),
    };
  }
  check("Text and mathematics retain their canonical order", finalText === canonical);
  report.font = font();
  scrollSpace.remove();
}
run()
  .catch((error) => report.errors.push(String(error)))
  .finally(() => {
    output.textContent = JSON.stringify(report);
    document.title = `Reader gestures: ${report.checks.length} checks, ${report.errors.length} failures${report.errors.length ? ": " + report.errors.join(", ") : ""}`;
    document.body.dataset.readingNavigationState = report.errors.length ? "error" : "ready";
    const summary = document.createElement("pre");
    summary.id = "reading-navigation-summary";
    summary.textContent = JSON.stringify({
      checks: report.checks.length,
      errors: report.errors,
      settings: report.settings,
      textDifference: report.textDifference,
    });
    document.body.append(summary);
  });

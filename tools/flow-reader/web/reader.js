import { MathDecorations } from "./decorations.js";
import { GraphicalAnnotations } from "./graphics.js";
import { TextAnnotations } from "./annotations.js";
import { AdaptiveCanvases } from "./canvases.js";
import { ContinuousSections } from "./sections.js";
import { logicalTextIndex } from "./math-identity.js";
import { ResponsiveMath } from "./math-renderer.js";
import { prepareResponsiveTables } from "./tables.js";
import { languageOf, setLanguage, uiLanguage } from "./language.js";
import { DrawingTheme } from "./drawing-theme.js";
import { ChangeLocationQueue } from "./change-location.js";
import { OutlineDrawer, ReaderGestures, readingSettings } from "./reading-navigation.js";

const article = document.querySelector("#reader-document");
const headingSelector = 'h1,h2,h3,h4,h5,h6,[role="heading"][aria-level]';
new DrawingTheme(article);
const status = document.querySelector("#reader-status");
const outline = document.querySelector("#reader-outline");
const menu = document.querySelector("#reader-menu");
const drawer = new OutlineDrawer(document.querySelector("#reader-navigation"), menu, {
  beforeOpen: updateOutlineLocation,
});
const settings = readingSettings(
  document.querySelector("#reader-appearance-panel"),
  document.querySelector("#reader-appearance-open"),
);
let gestures = null;
const defaultFontSize = 13;
// Start existing readers at the new requested default once. Subsequent explicit
// choices persist; the old setting and saved quotations/positions stay intact.
const fontSizeSetting = "fontSizeV2";
let storageKey = `flow-reader:${location.pathname}`;
let revision = null;
let pending = null;
let blocks = [];
let stableAnchor = null;
let stableScrollY = scrollY;
let anchorWidth = document.documentElement.clientWidth;
let fontSize = defaultFontSize;
let manifest = null;
let currentSection = null;
let loadSequence = 0;
let shellRevision = null;
const changedLocations = new ChangeLocationQueue(false);
const changeButton = document.querySelector("#reader-change-jump");
let lastChangeToken = null;
let lastUserGesture = -Infinity;
const recentGesture = () => performance.now() - lastUserGesture < 2500;
const markUserGesture = () => {
  lastUserGesture = performance.now();
};
for (const event of ["pointerdown", "touchmove", "wheel", "keydown"]) {
  document.addEventListener(event, markUserGesture, { passive: true });
}
changeButton.addEventListener("click", () => jumpToChange(changedLocations.lastLocation));
const sectionCache = new Map();
const footnoteSections = new Map();
const graphics = new GraphicalAnnotations(
  article,
  () => revision,
  (change) => {
    const anchor = readingAnchor();
    change();
    restoreAnchor(anchor);
  },
);
const canvases = new AdaptiveCanvases(
  article,
  () => revision,
  (change) => {
    const anchor = readingAnchor();
    change();
    restoreAnchor(anchor);
  },
  selectionActive,
);
const decorations = new MathDecorations(
  article,
  () => revision,
  () => graphics.schedule(),
  (change) => {
    const anchor = readingAnchor();
    change();
    restoreAnchor(anchor);
  },
);
const sections = new ContinuousSections(article, {
  fetchSection,
  prepare: prepareSection,
  changed: mountedSectionsChanged,
  anchor: readingAnchor,
  restore: restoreAnchor,
});
const mathematics = new ResponsiveMath(article, {
  preserve(change) {
    const anchor = readingAnchor();
    change();
    restoreAnchor(anchor);
  },
  changed() {
    decorations.sync();
    graphics.schedule();
    canvases.schedule();
    highlights?.repaint();
    sections.schedule();
    annotations.schedule();
  },
  selectionActive: textSelectionActive,
});
const annotations = new TextAnnotations(article, {
  async loadFootnote(target) {
    const document = manifest;
    const section = document?.anchors[target];
    if (!section) return null;
    const key = `${document.revision}:${section}`;
    if (!footnoteSections.has(key)) {
      const request = fetchSection(document, section)
        .then(parseDocument)
        .catch((error) => {
          footnoteSections.delete(key);
          throw error;
        });
      footnoteSections.set(key, request);
      while (footnoteSections.size > 6)
        footnoteSections.delete(footnoteSections.keys().next().value);
    }
    const parsed = await footnoteSections.get(key);
    if (manifest !== document) return null;
    const note = parsed.getElementById(target);
    if (!note?.closest('[role="doc-endnotes"]')) return null;
    const copy = note.cloneNode(true);
    setLanguage(copy, languageOf(note) ?? "");
    return copy;
  },
  prepareNote(note) {
    prepareNotes(note, note.id);
    prepareResponsiveTables(note);
    containWideMathematics(note);
    mathematics.prepare(note);
    mathematics.sync();
  },
  preserve(change) {
    const anchor = readingAnchor();
    change();
    restoreAnchor(anchor);
  },
  changed() {
    mathematics.schedule();
    decorations.schedule();
    sections.schedule();
  },
});
let highlights;
import("./highlights.js")
  .then(({ ReaderHighlights }) => {
    highlights = new ReaderHighlights(article);
    if (manifest && currentSection) highlights.onDocument(manifest, currentSection);
  })
  .catch(() => {
    // Keep reading available during a mixed-version development update.
    document.querySelector("#reader-selection").hidden = true;
  });

function readStored(key, fallback) {
  try {
    return JSON.parse(localStorage.getItem(`${storageKey}:${key}`)) ?? fallback;
  } catch {
    return fallback;
  }
}
function store(key, value) {
  try {
    localStorage.setItem(`${storageKey}:${key}`, JSON.stringify(value));
  } catch {
    /* Reading still works in private mode or when storage is full. */
  }
}
function fingerprint(text) {
  let hash = 2166136261;
  for (const char of text) {
    hash ^= char.codePointAt(0);
    hash = Math.imul(hash, 16777619);
  }
  return (hash >>> 0).toString(36);
}
function textOf(node) {
  return logicalTextIndex(node).text;
}

function readingAnchor() {
  const parked = [...article.querySelectorAll('[data-section-state="parked"]')].find((node) => {
    const rect = node.getBoundingClientRect();
    return rect.top <= 90 && rect.bottom > 90;
  });
  if (parked) {
    const rect = parked.getBoundingClientRect();
    return {
      section: parked.dataset.readerSection,
      fraction: (90 - rect.top) / rect.height,
      url: location.href,
    };
  }
  for (const canvas of article.querySelectorAll("[data-flow-canvas-model]")) {
    const area = canvas.getBoundingClientRect();
    if (area.top > 90 || area.bottom <= 90) continue;
    const labels = blocks
      .filter((node) => node.closest("[data-flow-canvas-model]") === canvas)
      .map((node) => ({ node, rect: node.getBoundingClientRect() }))
      .filter(({ rect }) => rect.height > 0 && rect.top <= 90 && rect.bottom > 90)
      .sort((a, b) => a.rect.left - b.rect.left);
    if (labels.length) {
      const { node, rect } = labels[0];
      return {
        key: node.dataset.readerKey,
        canvasIdentity: canvas.dataset.flowCanvasIdentity,
        text: textOf(node).slice(0, 180),
        offset: Math.round(rect.top) - 90,
        id: node.id,
        url: location.href,
        section: node.closest("[data-reader-section]")?.dataset.readerSection ?? currentSection,
      };
    }
    const geometry = canvas.querySelector(
      ":scope > .flow-canvas-stage > svg:not(.flow-canvas-leaders)",
    );
    const rect = geometry?.getBoundingClientRect();
    const plane = canvas.querySelector(":scope > .flow-canvas-stage")?.getBoundingClientRect();
    if (rect?.height > 0 && plane?.top <= 90 && plane.bottom > 90) {
      return {
        canvas: canvas.id,
        canvasIdentity: canvas.dataset.flowCanvasIdentity,
        canvasFraction: (90 - rect.top) / rect.height,
        text: logicalTextIndex(canvas, { includeNested: true }).text.slice(0, 180),
        section: canvas.closest("[data-reader-section]")?.dataset.readerSection ?? currentSection,
        id: canvas.id,
        url: location.href,
      };
    }
  }
  const block = blocks.find((node) => node.getBoundingClientRect().bottom > 90);
  if (!block) return null;
  return {
    key: block.dataset.readerKey,
    text: textOf(block).slice(0, 180),
    // CSS scroll positions are rounded. Keep one pixel target so hundreds of
    // automatic label publications cannot accumulate fractional scroll errors.
    offset: Math.round(block.getBoundingClientRect().top) - 90,
    section: block.closest("[data-reader-section]")?.dataset.readerSection ?? currentSection,
    id: block.id,
    url: location.href,
  };
}
function restoreAnchor(anchor) {
  if (!anchor) return;
  if (anchor.canvas && Number.isFinite(anchor.canvasFraction)) {
    const matchesText = (node) =>
      node?.hasAttribute("data-flow-canvas-model") &&
      logicalTextIndex(node, { includeNested: true }).text.startsWith(anchor.text);
    const matches = (node) =>
      matchesText(node) &&
      (!anchor.canvasIdentity || node.dataset.flowCanvasIdentity === anchor.canvasIdentity);
    let canvas = document.getElementById(anchor.canvas);
    if (!matches(canvas)) {
      const candidates = [...article.querySelectorAll("[data-flow-canvas-model]")].filter(matches);
      canvas = candidates.length === 1 ? candidates[0] : null;
    }
    if (!canvas && anchor.canvasIdentity) {
      const candidates = [...article.querySelectorAll("[data-flow-canvas-model]")].filter(
        matchesText,
      );
      canvas = candidates.length === 1 ? candidates[0] : null;
    }
    const rect = canvas
      ?.querySelector(":scope > .flow-canvas-stage > svg:not(.flow-canvas-leaders)")
      ?.getBoundingClientRect();
    if (rect?.height > 0) {
      window.scrollBy(0, rect.top + rect.height * anchor.canvasFraction - 90);
      if (document.documentElement.clientWidth === anchorWidth) {
        stableAnchor = anchor;
        stableScrollY = scrollY;
      }
    }
    return;
  }
  if (Number.isFinite(anchor.fraction)) {
    const section = article.querySelector(`[data-reader-section="${CSS.escape(anchor.section)}"]`);
    if (section) {
      const rect = section.getBoundingClientRect();
      window.scrollBy(0, rect.top + rect.height * anchor.fraction - 90);
      if (document.documentElement.clientWidth === anchorWidth) {
        stableAnchor = anchor;
        stableScrollY = scrollY;
      }
    }
    return;
  }
  const candidates = blocks.filter(
    (node) =>
      textOf(node).startsWith(anchor.text) &&
      (!anchor.canvasIdentity ||
        node.closest("[data-flow-canvas-model]")?.dataset.flowCanvasIdentity ===
          anchor.canvasIdentity),
  );
  const block =
    blocks.find((node) => node.dataset.readerKey === anchor.key) ??
    (candidates.length === 1 ? candidates[0] : null);
  if (block) {
    window.scrollBy(0, block.getBoundingClientRect().top - 90 - anchor.offset);
    if (document.documentElement.clientWidth === anchorWidth) {
      stableAnchor = anchor;
      stableScrollY = scrollY;
    }
  }
}
function setFont(size) {
  const anchor = readingAnchor();
  fontSize = Math.max(defaultFontSize, Math.min(30, size));
  document.documentElement.style.setProperty("--reader-font-size", `${fontSize}px`);
  document.querySelector("#reader-size").value = fontSize;
  document.querySelector("#reader-smaller").disabled = fontSize === defaultFontSize;
  document.querySelector("#reader-larger").disabled = fontSize === 30;
  store(fontSizeSetting, fontSize);
  mathematics.schedule();
  canvases.schedule();
  decorations.schedule();
  graphics.schedule();
  restoreAnchor(anchor);
}

window.addEventListener("resize", () => {
  // WebKit can change innerWidth during pinch zoom without changing layout.
  // Restore only after an actual text-width change, not a visual zoom or bar.
  const width = document.documentElement.clientWidth;
  if (width === anchorWidth) return;
  anchorWidth = width;
  restoreAnchor(stableAnchor);
});
document.fonts.addEventListener("loadingdone", () => {
  // A scroll can happen before its queued scroll event. A late font must not
  // restore the preceding passage over that newer navigation.
  if (Math.abs(scrollY - stableScrollY) < 1) restoreAnchor(stableAnchor);
});

function noteGroup(after) {
  let group = after.nextElementSibling;
  if (!group?.classList.contains("flow-notes")) {
    group = document.createElement("aside");
    group.className = "flow-notes";
    setLanguage(group, uiLanguage());
    group.setAttribute("aria-label", "수식 해설");
    after.after(group);
  }
  return group;
}

function prepareNotes(root, section) {
  const marks = new Map();
  let noteNumber = 0;
  // Traverse in document order: a repeated tag resolves to its preceding mark.
  const nodes = [...root.querySelectorAll("[data-flow-mark], [data-flow-targets]")];
  for (const node of nodes) {
    if (node.hasAttribute("data-flow-mark")) {
      marks.set(node.dataset.flowMark, node);
      continue;
    }
    const targets = JSON.parse(node.dataset.flowTargets);
    const targetNodes = targets.map((tag) => marks.get(tag));
    const destination =
      node.closest(".flow-equation") ?? node.closest("p") ?? node.closest("math") ?? node;
    const group = noteGroup(destination);
    const note = document.createElement("div");
    note.className = "flow-note";
    setLanguage(note, languageOf(node) ?? "");
    note.id = `reader-note-${section}-${++noteNumber}`;
    if (node.dataset.flowGraphic) {
      const id = node.dataset.flowGraphic;
      graphics.register(id, targets, targetNodes, note);
    } else {
      note.append(...node.childNodes);
      annotations.register(targetNodes, note);
    }
    if (node.dataset.flowDiagnostic) {
      note.classList.add("flow-unresolved");
      note.dataset.flowDiagnostic = node.dataset.flowDiagnostic;
    }
    group.append(note);
    for (const target of targets) {
      const mark = marks.get(target);
      if (!mark) continue;
      const ids = (mark.dataset.readerNote ?? "").split(" ").filter(Boolean);
      ids.push(note.id);
      mark.dataset.readerNote = ids.join(" ");
      mark.setAttribute("aria-details", ids.join(" "));
    }
    // Empty MathML token containers would otherwise retain unwanted spacing.
    const parent = node.parentElement;
    node.remove();
    if (parent?.localName === "mtext" && !parent.childNodes.length) parent.remove();
  }
}

function indexDocument() {
  let heading = "document";
  const counts = new Map();
  const blockSelector = `${headingSelector},p,.flow-equation,figcaption,div[id],td,th`;
  blocks = [...article.querySelectorAll(blockSelector)].filter(
    (node) =>
      !node.closest("svg,math,.flow-math-view,.flow-math-stage,.flow-notes,nav") &&
      !(node.matches("td,th") && node.querySelector("[data-reader-key]")) &&
      !(
        node.tagName === "DIV" &&
        !node.classList.contains("flow-equation") &&
        node.querySelector(blockSelector)
      ),
  );
  for (const node of blocks) {
    if (node.matches(headingSelector)) heading = node.id || fingerprint(textOf(node));
    if (node.dataset.readerKey) continue;
    const base = node.id || `${heading}-${fingerprint(textOf(node))}`;
    const count = (counts.get(base) ?? 0) + 1;
    counts.set(base, count);
    node.dataset.readerKey = `${base}:${count}`;
    if (!node.id) node.id = `reader-block-${base}-${count}`;
  }
}

function indexOutline(nextManifest) {
  outline.replaceChildren();
  const rootLevel = nextManifest.outline.reduce(
    (level, node) => Math.min(level, node.level),
    Infinity,
  );
  for (const node of nextManifest.outline) {
    const link = document.createElement("a");
    link.href = `#${encodeURIComponent(node.id)}`;
    link.textContent = node.title;
    link.dataset.level = node.level;
    link.style.setProperty("--outline-depth", node.level - rootLevel);
    setLanguage(link, nextManifest.language ?? "");
    outline.append(link);
  }
}

function updateOutlineLocation() {
  let current = null;
  let selected = null;
  let readingSection = null;
  const readingLine = 120;
  for (const section of article.querySelectorAll("[data-reader-section]")) {
    const rect = section.getBoundingClientRect();
    if (!rect.height) continue;
    readingSection ??= section.dataset.readerSection;
    if (rect.top <= readingLine) readingSection = section.dataset.readerSection;
    else break;
  }
  // A long passage can outlive its heading in the mounted reading window.
  // Use the complete outline for earlier sections, and geometry only within
  // the current section so a following heading cannot claim its preceding text.
  const sectionOrder = new Map(manifest?.sections.map((section, index) => [section.id, index]));
  const readingIndex = sectionOrder.get(readingSection);
  for (const heading of manifest?.outline ?? []) {
    const index = sectionOrder.get(heading.section);
    if (index < readingIndex) current = heading.id;
    else if (index === readingIndex) {
      const rect = article.querySelector(`#${CSS.escape(heading.id)}`)?.getBoundingClientRect();
      if (rect?.height && rect.top <= readingLine) current = heading.id;
    } else break;
  }
  for (const link of outline.querySelectorAll("a")) {
    if (decodeURIComponent(link.hash.slice(1)) === current) {
      link.setAttribute("aria-current", "location");
      selected = link;
    } else link.removeAttribute("aria-current");
  }
  if (selected) {
    selected.focus({ preventScroll: true });
    const list = outline.getBoundingClientRect();
    const item = selected.getBoundingClientRect();
    outline.scrollTop += item.top - list.top - (list.height - item.height) / 2;
  }
}

function containWideMathematics(root) {
  for (const math of root.querySelectorAll("math")) {
    if (math.closest("svg,.flow-equation") || math.parentElement.closest("math")) continue;
    const container = document.createElement("span");
    container.className = "flow-inline-equation";
    math.replaceWith(container);
    container.append(math);
  }
}

function textSelectionActive() {
  return (
    Boolean(gestures?.active) ||
    !window.getSelection()?.isCollapsed ||
    Boolean(document.querySelector("dialog[open]"))
  );
}

function selectionActive() {
  return Boolean(annotations.active) || textSelectionActive();
}

function parseDocument(html) {
  const parsed = new DOMParser().parseFromString(html, "text/html");
  // Typst output is document content; it does not control the reader shell.
  parsed.querySelectorAll("script,iframe,object,embed,form,base").forEach((node) => node.remove());
  for (const node of parsed.querySelectorAll("*")) {
    for (const attribute of [...node.attributes]) {
      if (
        /^on/i.test(attribute.name) ||
        (/^(href|src|xlink:href)$/i.test(attribute.name) &&
          /^\s*javascript:/i.test(attribute.value))
      ) {
        node.removeAttribute(attribute.name);
      }
    }
  }
  return parsed;
}

function prepareSection(html, section) {
  const parsed = parseDocument(html);
  if (shellRevision !== revision) {
    setLanguage(article, languageOf(parsed.body) ?? "");
    document
      .querySelector("#reader-document-styles")
      .replaceChildren(...parsed.head.querySelectorAll("style"));
    document.title = parsed.title ? `${parsed.title} · Flow Reader` : "Flow Reader";
    shellRevision = revision;
  }
  prepareNotes(parsed.body, section);
  annotations.prepareFootnotes(parsed.body, section);
  prepareResponsiveTables(parsed.body);
  containWideMathematics(parsed.body);
  graphics.prepare(parsed.body);
  mathematics.prepare(parsed.body);
  const content = document.createDocumentFragment();
  content.append(...parsed.body.childNodes);
  return content;
}

function mountedSectionsChanged() {
  indexDocument();
  mathematics.sync();
  graphics.sync();
  canvases.sync();
  decorations.sync();
  annotations.sync();
  highlights?.repaint();
}

function renderDocument(html, nextManifest, section, options) {
  const sequence = loadSequence;
  annotations.clear();
  mathematics.clear();
  graphics.clear();
  decorations.clear();
  revision = nextManifest.revision;
  manifest = nextManifest;
  currentSection = section;
  sections.reset(manifest, section, html);
  indexDocument();
  mathematics.sync();
  article.setAttribute("aria-busy", "false");
  canvases.onDocument();
  decorations.sync();
  graphics.sync();
  highlights?.onDocument(manifest, currentSection);
  indexOutline(manifest);
  pending = null;
  requestAnimationFrame(() => {
    if (revision !== nextManifest.revision || sequence !== loadSequence) return;
    if (options.target) document.getElementById(options.target)?.scrollIntoView();
    else if (options.anchor) restoreAnchor(options.anchor);
    else window.scrollTo(0, 0);
    sections.schedule();
    const change = changedLocations.afterRender(performance.now(), lastUserGesture);
    if (change) {
      if (change.deferred) changeButton.hidden = false;
      else jumpToChange(change.location, true);
    }
  });
}

async function jumpToChange(change, automatic = false) {
  if (!change || !manifest || change.revision !== revision) return;
  if (automatic && (recentGesture() || selectionActive())) {
    changeButton.hidden = false;
    return;
  }
  const local = document.getElementById(change.target);
  if (local && article.contains(local)) {
    loadSequence++;
    local.scrollIntoView({ behavior: "instant" });
    stableAnchor = readingAnchor();
    stableScrollY = scrollY;
    sections.schedule();
    changeButton.hidden = true;
  } else {
    await loadSection(manifest, change.section, {
      target: change.target,
      changeToken: change.token,
      automaticChange: automatic,
    });
  }
}

function queueChange(nextManifest, explicit) {
  const change = nextManifest.lastChange;
  if (
    !change ||
    change.revision !== nextManifest.revision ||
    nextManifest.anchors[change.target] !== change.section
  ) {
    changedLocations.clear();
    changeButton.hidden = true;
    return;
  }
  if (changedLocations.lastLocation?.token === change.token) {
    changedLocations.lastLocation = change;
  }
  if (lastChangeToken === change.token) return;
  lastChangeToken = change.token;
  changedLocations.clear();
  changeButton.hidden = true;
  if (!explicit) changedLocations.queue(change, !revision);
}

function fragment() {
  try {
    return decodeURIComponent(location.hash.slice(1));
  } catch {
    return "";
  }
}

async function fetchSection(nextManifest, section, signal) {
  const key = `${nextManifest.revision}:${section}`;
  let html = sectionCache.get(key);
  if (!html) {
    const response = await fetch(
      `api/sections/${encodeURIComponent(section)}?revision=${nextManifest.revision}`,
      { signal },
    );
    if (!response.ok) throw new Error(`Section HTTP ${response.status}`);
    html = await response.text();
  }
  sectionCache.delete(key);
  sectionCache.set(key, html);
  while (sectionCache.size > 6) sectionCache.delete(sectionCache.keys().next().value);
  return html;
}

function navigationHistory(section, target) {
  history.replaceState({ readerAnchor: readingAnchor() }, "", location.href);
  const url = new URL(location.href);
  url.searchParams.set("section", section);
  url.hash = target ? encodeURIComponent(target) : "";
  history.pushState(null, "", url);
}

async function loadSection(nextManifest, section, options = {}) {
  const sequence = ++loadSequence;
  article.setAttribute("aria-busy", "true");
  try {
    const html = await fetchSection(nextManifest, section);
    if (sequence !== loadSequence) return;
    if (options.changeToken) {
      if (nextManifest.revision !== revision || options.changeToken !== lastChangeToken) return;
      if (options.automaticChange && (recentGesture() || selectionActive())) {
        changeButton.hidden = false;
        return;
      }
      changeButton.hidden = true;
    }
    // A source update must not dismiss a note or disturb a selection made while
    // its network request was in flight. Explicit navigation is the user's choice.
    if (options.update && selectionActive()) {
      pending = nextManifest;
      return;
    }
    if (options.update && revision) {
      options.anchor = readingAnchor();
      const destination = sectionFor(nextManifest, options.anchor, options.target);
      if (destination !== section) return loadSection(nextManifest, destination, options);
    }
    if (options.history) navigationHistory(section, options.target);
    renderDocument(html, nextManifest, section, options);
  } catch {
    if (options.changeToken) changeButton.hidden = false;
    status.dataset.state = "error";
    status.textContent = "이 절을 불러오지 못했습니다. 현재 내용은 계속 읽을 수 있습니다.";
  } finally {
    if (sequence === loadSequence) article.setAttribute("aria-busy", "false");
  }
}

function sectionFor(nextManifest, anchor, target) {
  return (
    nextManifest.anchors[target] ??
    nextManifest.blocks[anchor?.key] ??
    nextManifest.canvasIdentities?.[anchor?.canvasIdentity] ??
    nextManifest.anchors[anchor?.id] ??
    nextManifest.sections.find((section) => section.id === anchor?.section)?.id ??
    nextManifest.sections[0].id
  );
}

async function navigateAnchor(target, push = true) {
  if (!manifest) return;
  const section = manifest.anchors[target];
  const local = annotations.footnote(target) ?? document.getElementById(target);
  if (local && article.contains(local)) {
    // A newer local jump must supersede an earlier remote jump still fetching.
    loadSequence++;
    article.setAttribute("aria-busy", "false");
    if (push) navigationHistory(section ?? currentSection, target);
    local.scrollIntoView();
    if (local.dataset.noteKind === "footnote") local.focus({ preventScroll: true });
  } else if (section) {
    await loadSection(manifest, section, { target, history: push });
  }
}

window.addEventListener("popstate", (event) => {
  if (!manifest) return;
  const anchor = event.state?.readerAnchor;
  if (anchor) loadSection(manifest, sectionFor(manifest, anchor), { anchor });
  else if (fragment()) navigateAnchor(fragment(), false);
  else {
    const id = new URL(location.href).searchParams.get("section") ?? manifest.sections[0].id;
    if (manifest.sections.some((section) => section.id === id)) loadSection(manifest, id);
  }
});

article.addEventListener("click", (event) => {
  const link = event.target.closest('a[href^="#"]');
  if (link && !event.metaKey && !event.ctrlKey && !event.shiftKey) {
    event.preventDefault();
    navigateAnchor(decodeURIComponent(link.getAttribute("href").slice(1)));
    return;
  }
});
document.querySelector("#reader-smaller").addEventListener("click", () => setFont(fontSize - 1));
document.querySelector("#reader-larger").addEventListener("click", () => setFont(fontSize + 1));
outline.addEventListener("click", async (event) => {
  const link = event.target.closest("a");
  if (link) {
    event.preventDefault();
    drawer.close();
    await navigateAnchor(decodeURIComponent(link.hash.slice(1)));
    article.focus({ preventScroll: true });
  }
});
gestures = new ReaderGestures(article, drawer, {
  getFont: () => fontSize,
  setFont,
  preview: document.querySelector("#reader-font-preview"),
  announce: document.querySelector("#reader-gesture-message"),
});
let saveTimer;
history.scrollRestoration = "manual";
function savePosition() {
  const anchor = readingAnchor();
  if (!anchor) return;
  store("position", anchor);
  history.replaceState({ readerAnchor: anchor }, "", location.href);
}
window.addEventListener(
  "scroll",
  () => {
    if (document.documentElement.clientWidth === anchorWidth) {
      stableAnchor = readingAnchor();
      stableScrollY = scrollY;
    }
    clearTimeout(saveTimer);
    saveTimer = setTimeout(savePosition, 300);
  },
  { passive: true },
);
window.addEventListener("pagehide", savePosition);
setFont(Number(readStored(fontSizeSetting, defaultFontSize)) || defaultFontSize);

async function refresh() {
  try {
    const response = await fetch("api/state", { cache: "no-store" });
    if (!response.ok) throw new Error(`HTTP ${response.status}`);
    const state = await response.json();
    // An identical revision can survive a service restart. New selections use
    // its new identity; already captured selections retain the old identity.
    if (manifest && state.revision === manifest.revision) manifest.service = state.service;
    const documentStorageKey = state.documentID ? `flow-reader:${state.documentID}` : storageKey;
    if (documentStorageKey !== storageKey) {
      storageKey = documentStorageKey;
      setFont(Number(readStored(fontSizeSetting, defaultFontSize)) || defaultFontSize);
    }
    status.dataset.state = state.compiling
      ? "compiling"
      : state.exitCode
        ? "error"
        : state.contentGatePassed && !state.development
          ? "ready"
          : "incomplete";
    status.textContent = state.compiling
      ? "저장된 변경 사항을 반영하는 중…"
      : state.exitCode
        ? "컴파일 오류가 있어 마지막으로 읽을 수 있었던 문서를 표시합니다."
        : state.contentGatePassed && !state.development
          ? ""
          : "개발 중인 읽기 화면입니다. 일부 그림·주석은 원본 확인이 필요합니다.";
    if (state.revision && state.revision !== revision && state.revision !== pending?.revision) {
      const manifestResponse = await fetch(
        `api/manifest?revision=${encodeURIComponent(state.revision)}`,
      );
      if (!manifestResponse.ok) throw new Error(`HTTP ${manifestResponse.status}`);
      pending = await manifestResponse.json();
    }
    if (pending && !selectionActive()) {
      const entryAnchor = !revision ? history.state?.readerAnchor : null;
      const anchor = revision ? readingAnchor() : (entryAnchor ?? readStored("position", null));
      const navigationType = performance.getEntriesByType("navigation")[0]?.type;
      const resuming =
        !revision &&
        anchor?.url === location.href &&
        (Boolean(entryAnchor) || ["reload", "back_forward"].includes(navigationType));
      const target = !revision && !resuming ? fragment() : null;
      // New named links take precedence over a previous session's position.
      // Reload/history navigation restores its entry; section queries are entry hints.
      const sectionHint =
        !revision && !resuming && new URL(location.href).searchParams.get("section");
      queueChange(
        pending,
        !revision && (Boolean(target) || Boolean(sectionHint) || navigationType === "back_forward"),
      );
      const section =
        sectionHint && pending.sections.some((item) => item.id === sectionHint)
          ? (pending.anchors[target] ?? sectionHint)
          : sectionFor(pending, anchor, target);
      await loadSection(pending, section, { anchor, target, update: true });
    }
  } catch {
    status.dataset.state = "error";
    status.textContent = revision
      ? "연결이 끊겼습니다. 현재 문서는 계속 읽을 수 있습니다."
      : "문서를 불러오지 못했습니다. 연결을 확인하고 다시 시도합니다.";
  } finally {
    setTimeout(refresh, 3000);
  }
}
refresh();

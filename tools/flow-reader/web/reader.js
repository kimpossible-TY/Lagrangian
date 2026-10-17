import { MathDecorations } from "./decorations.js";
import { GraphicalAnnotations, namespaceClone } from "./graphics.js";
import { AdaptiveCanvases } from "./canvases.js";
import { ContinuousSections } from "./sections.js";
import { logicalTextIndex } from "./math-identity.js";
import { ResponsiveMath } from "./math-renderer.js";

const article = document.querySelector("#reader-document");
const status = document.querySelector("#reader-status");
const outline = document.querySelector("#reader-outline");
const menu = document.querySelector("#reader-menu");
let storageKey = `flow-reader:${location.pathname}`;
let revision = null;
let pending = null;
let blocks = [];
let fontSize = 18;
let manifest = null;
let currentSection = null;
let loadSequence = 0;
let shellRevision = null;
const sectionCache = new Map();
const graphics = new GraphicalAnnotations(
  article,
  () => revision,
  (change) => {
    const anchor = readingAnchor();
    change();
    restoreAnchor(anchor);
  },
);
const canvases = new AdaptiveCanvases(article, () => revision);
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
    highlights?.repaint();
    sections.schedule();
  },
  selectionActive,
});
let highlights;
import("./highlights.js")
  .then(({ ReaderHighlights }) => {
    highlights = new ReaderHighlights(article, navigateAnchor);
    if (manifest && currentSection) highlights.onDocument(manifest, currentSection);
  })
  .catch(() => {
    // Keep reading available during a mixed-version development update.
    document.querySelector("#reader-highlights-open").hidden = true;
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
  const block = blocks.find((node) => node.getBoundingClientRect().bottom > 90);
  if (!block) return null;
  return {
    key: block.dataset.readerKey,
    text: textOf(block).slice(0, 180),
    offset: block.getBoundingClientRect().top - 90,
    section: block.closest("[data-reader-section]")?.dataset.readerSection ?? currentSection,
    id: block.id,
    url: location.href,
  };
}
function restoreAnchor(anchor) {
  if (!anchor) return;
  if (Number.isFinite(anchor.fraction)) {
    const section = article.querySelector(`[data-reader-section="${CSS.escape(anchor.section)}"]`);
    if (section) {
      const rect = section.getBoundingClientRect();
      window.scrollBy(0, rect.top + rect.height * anchor.fraction - 90);
    }
    return;
  }
  const block =
    blocks.find((node) => node.dataset.readerKey === anchor.key) ??
    blocks.find((node) => textOf(node).startsWith(anchor.text));
  if (block) window.scrollBy(0, block.getBoundingClientRect().top - 90 - anchor.offset);
}
function setFont(size) {
  const anchor = readingAnchor();
  fontSize = Math.max(14, Math.min(30, size));
  document.documentElement.style.setProperty("--reader-font-size", `${fontSize}px`);
  document.querySelector("#reader-size").value = fontSize;
  document.querySelector("#reader-smaller").disabled = fontSize === 14;
  document.querySelector("#reader-larger").disabled = fontSize === 30;
  store("fontSize", fontSize);
  mathematics.schedule();
  canvases.schedule();
  decorations.schedule();
  graphics.schedule();
  requestAnimationFrame(() => restoreAnchor(anchor));
}

function noteGroup(after) {
  let group = after.nextElementSibling;
  if (!group?.classList.contains("flow-notes")) {
    group = document.createElement("aside");
    group.className = "flow-notes";
    group.setAttribute("aria-label", "수식 해설");
    after.after(group);
  }
  return group;
}

function noteTargets(nodes, prefix) {
  const heading = document.createElement("div");
  heading.className = "flow-note-targets";
  heading.setAttribute("aria-label", "해설 대상");
  nodes.forEach((node, index) => {
    if (!node) return;
    const copy = namespaceClone(node.cloneNode(true), `${prefix}-${index}-`);
    for (const child of [copy, ...copy.querySelectorAll("*")]) {
      for (const name of [
        "data-reader-key",
        "data-flow-mark",
        "data-reader-note",
        "aria-details",
        "aria-describedby",
        "tabindex",
        "role",
        "aria-haspopup",
      ])
        child.removeAttribute(name);
    }
    copy.querySelectorAll("[data-flow-targets]").forEach((child) => child.remove());
    if (index) heading.append(document.createTextNode(" · "));
    if (copy.namespaceURI === "http://www.w3.org/1998/Math/MathML" && copy.localName !== "math") {
      const math = document.createElementNS("http://www.w3.org/1998/Math/MathML", "math");
      math.append(copy);
      heading.append(math);
    } else heading.append(copy);
  });
  return heading;
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
    note.id = `reader-note-${section}-${++noteNumber}`;
    if (node.dataset.flowGraphic) {
      const id = node.dataset.flowGraphic;
      graphics.register(id, targets, targetNodes, note);
    } else {
      note.append(noteTargets(targetNodes, note.id));
      note.append(...node.childNodes);
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
  blocks = [...article.querySelectorAll("h1,h2,h3,h4,h5,p,.flow-equation,figcaption")].filter(
    (node) => !node.closest("svg,math,.flow-notes,nav"),
  );
  for (const node of blocks) {
    if (/^H[1-5]$/.test(node.tagName)) heading = node.id || fingerprint(textOf(node));
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
  for (const node of nextManifest.outline) {
    const link = document.createElement("a");
    link.href = `#${encodeURIComponent(node.id)}`;
    link.textContent = node.title;
    link.dataset.level = node.level;
    outline.append(link);
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

function selectionActive() {
  return !window.getSelection()?.isCollapsed || Boolean(document.querySelector("dialog[open]"));
}

function prepareSection(html, section) {
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
  if (shellRevision !== revision) {
    document
      .querySelector("#reader-document-styles")
      .replaceChildren(...parsed.head.querySelectorAll("style"));
    document.title = parsed.title ? `${parsed.title} · Flow Reader` : "Flow Reader";
    shellRevision = revision;
  }
  prepareNotes(parsed.body, section);
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
  highlights?.repaint();
}

function renderDocument(html, nextManifest, section, options) {
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
    if (options.target) document.getElementById(options.target)?.scrollIntoView();
    else if (options.anchor) restoreAnchor(options.anchor);
    else window.scrollTo(0, 0);
    sections.schedule();
  });
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
    nextManifest.anchors[anchor?.id] ??
    nextManifest.sections.find((section) => section.id === anchor?.section)?.id ??
    nextManifest.sections[0].id
  );
}

async function navigateAnchor(target, push = true) {
  if (!manifest) return;
  const section = manifest.anchors[target];
  const local = document.getElementById(target);
  if (local && article.contains(local)) {
    // A newer local jump must supersede an earlier remote jump still fetching.
    loadSequence++;
    article.setAttribute("aria-busy", "false");
    if (push) navigationHistory(section ?? currentSection, target);
    local.scrollIntoView();
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
document.querySelector("#reader-smaller").addEventListener("click", () => setFont(fontSize - 2));
document.querySelector("#reader-larger").addEventListener("click", () => setFont(fontSize + 2));
menu.addEventListener("click", () => {
  outline.hidden = !outline.hidden;
  menu.setAttribute("aria-expanded", !outline.hidden);
});
outline.addEventListener("click", (event) => {
  const link = event.target.closest("a");
  if (link) {
    event.preventDefault();
    outline.hidden = true;
    menu.setAttribute("aria-expanded", "false");
    navigateAnchor(decodeURIComponent(link.hash.slice(1)));
  }
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
    clearTimeout(saveTimer);
    saveTimer = setTimeout(savePosition, 300);
  },
  { passive: true },
);
window.addEventListener("pagehide", savePosition);
setFont(Number(readStored("fontSize", 18)) || 18);

async function refresh() {
  try {
    const response = await fetch("api/state", { cache: "no-store" });
    if (!response.ok) throw new Error(`HTTP ${response.status}`);
    const state = await response.json();
    const documentStorageKey = state.documentID ? `flow-reader:${state.documentID}` : storageKey;
    if (documentStorageKey !== storageKey) {
      storageKey = documentStorageKey;
      setFont(Number(readStored("fontSize", 18)) || 18);
    }
    const original = document.querySelector("#reader-original");
    if (state.originalURL) {
      original.href = state.originalURL;
      original.hidden = false;
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
          ? "저장된 문서 · 화면에 맞춰 읽기"
          : "개발 중인 읽기 화면입니다. 일부 그림·주석은 원본 확인이 필요합니다.";
    if (state.revision && state.revision !== revision && state.revision !== pending?.revision) {
      const manifestResponse = await fetch(
        `api/manifest?revision=${encodeURIComponent(state.revision)}`,
      );
      if (!manifestResponse.ok) throw new Error(`HTTP ${manifestResponse.status}`);
      pending = await manifestResponse.json();
    }
    if (pending && !selectionActive()) {
      const anchor = revision ? readingAnchor() : readStored("position", null);
      const target = !revision && anchor?.url !== location.href ? fragment() : null;
      // A reload resumes the saved block. A section query is an entry hint only
      // when the URL differs from the saved location (e.g. a newly opened link).
      const sectionHint =
        !revision &&
        anchor?.url !== location.href &&
        new URL(location.href).searchParams.get("section");
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

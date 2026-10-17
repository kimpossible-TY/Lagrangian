import { GraphicalAnnotations, namespaceClone } from "./graphics.js";

const article = document.querySelector("#reader-document");
const status = document.querySelector("#reader-status");
const outline = document.querySelector("#reader-outline");
const menu = document.querySelector("#reader-menu");
const noteDialog = document.querySelector("#reader-note");
const storageKey = `flow-reader:${location.pathname}`;
let revision = null;
let pending = null;
let blocks = [];
let fontSize = 18;
let manifest = null;
let currentSection = null;
let loadSequence = 0;
const sectionCache = new Map();
const graphics = new GraphicalAnnotations(noteDialog, () => revision);

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
  return node.textContent.replace(/\s+/g, " ").trim();
}

function readingAnchor() {
  const block = blocks.find((node) => node.getBoundingClientRect().bottom > 90);
  if (!block) return null;
  return {
    key: block.dataset.readerKey,
    text: textOf(block).slice(0, 180),
    offset: block.getBoundingClientRect().top - 90,
    section: currentSection,
    id: block.id,
    url: location.href,
  };
}
function restoreAnchor(anchor) {
  if (!anchor) return;
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
  requestAnimationFrame(() => restoreAnchor(anchor));
}

function noteGroup(after) {
  let group = after.nextElementSibling;
  if (!group?.classList.contains("flow-notes")) {
    group = document.createElement("details");
    group.className = "flow-notes";
    const summary = document.createElement("summary");
    summary.textContent = "수식 해설";
    group.append(summary);
    after.after(group);
  }
  return group;
}

function prepareNotes(root) {
  graphics.clear();
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
    const destination = node.closest(".flow-equation") ?? node.closest("p") ?? node;
    const group = noteGroup(destination);
    const note = document.createElement("div");
    note.className = "flow-note";
    note.id = `reader-note-${++noteNumber}`;
    if (node.dataset.flowGraphic) {
      const id = node.dataset.flowGraphic;
      graphics.register(
        id,
        targets,
        targets.map((tag) => marks.get(tag)),
      );
      const button = document.createElement("button");
      button.className = "flow-graphic-open";
      button.dataset.graphicId = id;
      button.textContent = "관계 그림 보기";
      note.append(button);
    } else {
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
      mark.setAttribute("tabindex", "0");
      mark.setAttribute("role", "button");
      mark.setAttribute("aria-label", `${textOf(mark) || "표시된 수식"}: 해설 보기`);
      mark.setAttribute("aria-haspopup", "dialog");
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
  return !window.getSelection()?.isCollapsed || noteDialog.open;
}

function renderDocument(html, nextManifest, section, options) {
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
  document
    .querySelector("#reader-document-styles")
    .replaceChildren(...parsed.head.querySelectorAll("style"));
  prepareNotes(parsed.body);
  containWideMathematics(parsed.body);
  article.replaceChildren(...parsed.body.childNodes);
  document.title = parsed.title ? `${parsed.title} · Flow Reader` : "Flow Reader";
  indexDocument();
  article.setAttribute("aria-busy", "false");
  revision = nextManifest.revision;
  manifest = nextManifest;
  currentSection = section;
  indexOutline(manifest);
  updateSectionNavigation();
  pending = null;
  requestAnimationFrame(() => {
    if (options.target) document.getElementById(options.target)?.scrollIntoView();
    else if (options.anchor) restoreAnchor(options.anchor);
    else window.scrollTo(0, 0);
  });
}

function fragment() {
  try {
    return decodeURIComponent(location.hash.slice(1));
  } catch {
    return "";
  }
}

async function loadSection(nextManifest, section, options = {}) {
  const sequence = ++loadSequence;
  const key = `${nextManifest.revision}:${section}`;
  article.setAttribute("aria-busy", "true");
  try {
    let html = sectionCache.get(key);
    if (!html) {
      const response = await fetch(
        `api/sections/${encodeURIComponent(section)}?revision=${nextManifest.revision}`,
      );
      if (!response.ok) throw new Error(`Section HTTP ${response.status}`);
      html = await response.text();
      sectionCache.set(key, html);
      while (sectionCache.size > 6) sectionCache.delete(sectionCache.keys().next().value);
    }
    if (sequence !== loadSequence) return;
    // A source update must not dismiss a note or disturb a selection made while
    // its network request was in flight. Explicit navigation is the user's choice.
    if (options.update && selectionActive()) {
      pending = nextManifest;
      return;
    }
    renderDocument(html, nextManifest, section, options);
    if (options.history) {
      const url = new URL(location.href);
      url.searchParams.set("section", section);
      url.hash = options.target ? encodeURIComponent(options.target) : "";
      history.pushState(null, "", url);
    }
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

function updateSectionNavigation() {
  const index = manifest.sections.findIndex((section) => section.id === currentSection);
  document.querySelector("#reader-section-name").textContent =
    `${index + 1} / ${manifest.sections.length} · ${manifest.sections[index].title}`;
  document.querySelector("#reader-previous").disabled = index === 0;
  document.querySelector("#reader-next").disabled = index === manifest.sections.length - 1;
  document.querySelector("#reader-section-navigation").hidden = false;
}

async function navigateAnchor(target, push = true) {
  if (!manifest) return;
  const section = manifest.anchors[target];
  const local = document.getElementById(target);
  if (local && (!section || section === currentSection)) {
    local.scrollIntoView();
    if (push) history.pushState(null, "", `#${encodeURIComponent(target)}`);
  } else if (section) {
    await loadSection(manifest, section, { target, history: push });
  }
}

for (const [id, direction] of [
  ["reader-previous", -1],
  ["reader-next", 1],
]) {
  document.getElementById(id).addEventListener("click", () => {
    const index = manifest.sections.findIndex((section) => section.id === currentSection);
    const next = manifest.sections[index + direction];
    if (next) loadSection(manifest, next.id, { history: true });
  });
}
window.addEventListener("popstate", () => {
  if (!manifest) return;
  if (fragment()) navigateAnchor(fragment(), false);
  else {
    const id = new URL(location.href).searchParams.get("section") ?? manifest.sections[0].id;
    if (manifest.sections.some((section) => section.id === id)) loadSection(manifest, id);
  }
});

function showNote(mark) {
  const notes = mark.dataset.readerNote
    .split(" ")
    .map((id) => document.getElementById(id))
    .filter(Boolean);
  const body = document.querySelector("#reader-note-body");
  if (notes.length === 1 && notes[0].querySelector(".flow-graphic-open")) {
    graphics.show(notes[0].querySelector(".flow-graphic-open").dataset.graphicId);
    return;
  }
  body.replaceChildren(
    ...notes.map((note, i) => namespaceClone(note.cloneNode(true), `reader-dialog-${i}-`)),
  );
  noteDialog.showModal();
}
article.addEventListener("click", (event) => {
  const link = event.target.closest('a[href^="#"]');
  if (link && !event.metaKey && !event.ctrlKey && !event.shiftKey) {
    event.preventDefault();
    navigateAnchor(decodeURIComponent(link.getAttribute("href").slice(1)));
    return;
  }
  const graphic = event.target.closest(".flow-graphic-open");
  if (graphic) {
    graphics.show(graphic.dataset.graphicId);
    return;
  }
  const mark = event.target.closest("[data-reader-note]");
  if (mark && window.getSelection()?.isCollapsed) showNote(mark);
});
noteDialog.addEventListener("click", (event) => {
  const graphic = event.target.closest(".flow-graphic-open");
  if (graphic) graphics.show(graphic.dataset.graphicId);
});
article.addEventListener("keydown", (event) => {
  const mark = event.target.closest("[data-reader-note]");
  if (mark && (event.key === "Enter" || event.key === " ")) {
    event.preventDefault();
    showNote(mark);
  }
});
document.querySelector("#reader-note-close").addEventListener("click", () => noteDialog.close());
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
window.addEventListener(
  "scroll",
  () => {
    clearTimeout(saveTimer);
    saveTimer = setTimeout(() => store("position", readingAnchor()), 300);
  },
  { passive: true },
);
window.addEventListener("pagehide", () => store("position", readingAnchor()));
setFont(Number(readStored("fontSize", 18)) || 18);

async function refresh() {
  try {
    const response = await fetch("api/state", { cache: "no-store" });
    if (!response.ok) throw new Error(`HTTP ${response.status}`);
    const state = await response.json();
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
      const sectionHint = !revision && new URL(location.href).searchParams.get("section");
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

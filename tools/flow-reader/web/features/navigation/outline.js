import { setLanguage } from "../../ui/language.js";

export function createOutline(article, outline, readManifest) {
  function index(nextManifest) {
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

  function updateLocation() {
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
    const sectionOrder = new Map(
      readManifest()?.sections.map((section, index) => [section.id, index]),
    );
    const readingIndex = sectionOrder.get(readingSection);
    for (const heading of readManifest()?.outline ?? []) {
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

  return { index, updateLocation };
}

// Test-only observation: no input synthesis or application-state changes.
const diagnostic = document.createElement("aside");
diagnostic.className = "fixture-diagnostic";
diagnostic.setAttribute("aria-label", "합성 메뉴 수명 관찰");
const title = document.createElement("h2");
title.textContent =
  location.pathname === "/slow/" ? "느린 합성 메뉴 검수" : "일반 속도 합성 메뉴 검수";
const status = document.createElement("p");
status.setAttribute("role", "status");
status.textContent = "아직 관찰된 이벤트 없음";
const history = document.createElement("details");
const summary = document.createElement("summary");
summary.textContent = "최근 관찰 이력 (최대 24개)";
const entries = document.createElement("ol");
entries.setAttribute("aria-label", "합성 메뉴 이벤트 이력");
history.append(summary, entries);
diagnostic.append(title, status, history);
document.body.prepend(diagnostic);

// The production card does not expose its inventory ID. Give its actual DOM
// node a stable observation ID and show the public document title alongside it.
const cardIds = new WeakMap();
const menuIds = new WeakMap();
let nextCard = 0;
let nextMenu = 0;
function idFor(ids, element, next) {
  if (!ids.has(element)) ids.set(element, next());
  return ids.get(element);
}
function describe(element) {
  if (!element) return "없음";
  const card = element.closest?.(".document-card");
  const menu = element.closest?.("wa-dropdown");
  const parts = [];
  if (card) {
    const id = idFor(cardIds, card, () => ++nextCard);
    const name = card.querySelector(".document-info h3")?.textContent || "제목 없음";
    parts.push(`문서 ${id} (${name})`);
  }
  if (menu) parts.push(`메뉴 ${idFor(menuIds, menu, () => ++nextMenu)}`);
  parts.push(element.getAttribute?.("aria-label") || element.id || element.localName || "없음");
  return parts.join(" / ");
}
let count = 0;
for (const type of ["wa-show", "wa-hide", "wa-after-show", "wa-after-hide", "focusin"]) {
  document.addEventListener(type, (event) => {
    const focused = describe(document.activeElement);
    const source = describe(event.target);
    const line = `${++count} · ${performance.now().toFixed(2)} ms · ${type} · 출처: ${source} · 포커스: ${focused}`;
    status.textContent = line;
    const entry = document.createElement("li");
    entry.textContent = line;
    entries.append(entry);
    if (entries.children.length > 24) entries.firstElementChild.remove();
  });
}

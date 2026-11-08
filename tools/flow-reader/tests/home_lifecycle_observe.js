// Test-only observation: no input synthesis or application-state changes.
const diagnostic = document.createElement("aside");
diagnostic.setAttribute("aria-label", "합성 메뉴 수명 관찰");
const title = document.createElement("h2");
title.textContent =
  location.pathname === "/slow/" ? "느린 합성 메뉴 검수" : "일반 속도 합성 메뉴 검수";
const status = document.createElement("p");
status.setAttribute("role", "status");
status.textContent = "아직 관찰된 이벤트 없음";
diagnostic.append(title, status);
document.body.prepend(diagnostic);
let count = 0;
for (const type of ["wa-show", "wa-hide", "wa-after-show", "wa-after-hide", "focusin"]) {
  document.addEventListener(type, (event) => {
    const focused = document.activeElement;
    const name = focused?.getAttribute("aria-label") || focused?.id || focused?.localName || "없음";
    status.textContent = `${++count} · ${type} · 포커스: ${name}`;
  });
}

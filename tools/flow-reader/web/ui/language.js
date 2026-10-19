const xml = "http://www.w3.org/XML/1998/namespace";
const html = "http://www.w3.org/1999/xhtml";

export function languageOf(node) {
  for (let current = node; current; current = current.parentElement) {
    const value = current.getAttributeNS(xml, "lang") ?? current.getAttribute("lang");
    if (value !== null) return value;
  }
  return null;
}

export function setLanguage(node, value) {
  node.removeAttribute("lang");
  node.removeAttributeNS(xml, "lang");
  if (typeof value !== "string") return;
  // Empty language means unknown; it must not inherit the Korean Reader UI.
  if (node.namespaceURI === html) node.setAttribute("lang", value);
  else node.setAttributeNS(xml, "xml:lang", value);
}

export function uiLanguage() {
  return document.documentElement?.lang || "ko";
}

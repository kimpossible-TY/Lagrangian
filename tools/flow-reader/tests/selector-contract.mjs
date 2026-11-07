// Only literal shell attributes belong here; rendered structures are checked in ui-baseline.mjs.
export const shells = {
  home: ['id="documents"', 'id="document-list"', 'id="document-search"', 'id="reader-theme"', 'aria-label="홈 탐색"', 'data-oai-siwc-button'],
  reader: ['id="reader-document"', 'id="reader-menu"', 'id="reader-navigation"', 'id="reader-selection"', 'id="reader-chat-ask"', 'aria-label="Ask about this paragraph"', 'data-appearance="system"'],
};

export function checkShell(name, html) {
  const tags = html.replace(/<!--[\s\S]*?-->/g, "").match(/<[a-z][^>]*>/gi) || [];
  const missing = shells[name].filter((attribute) => !tags.some((tag) => tag.includes(attribute)));
  if (missing.length) throw new Error(`${name} shell missing hooks: ${missing.join(", ")}`);
}

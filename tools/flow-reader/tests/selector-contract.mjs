// Only literal shell attributes belong here; rendered structures are checked in ui-baseline.mjs.
export const shells = {
  home: ['id="documents"', 'id="document-list"', 'id="document-search"', 'id="reader-theme"', 'aria-label="홈 탐색"', 'data-oai-siwc-button'],
  reader: ['id="reader-document"', 'class="reader-logo-home-link"', 'id="reader-menu"', 'id="reader-navigation"', 'id="reader-selection"', 'id="reader-chat-ask"', 'aria-label="Ask about this paragraph"', 'data-appearance="system"'],
};

export function checkShell(name, html) {
  const tags = html.replace(/<!--[\s\S]*?-->/g, "").match(/<[a-z][^\s/>]*(?:\s+(?:[^"'>]|"[^"]*"|'[^']*')*)?\s*\/?\s*>/gi) || [];
  const attributes = tags.flatMap((tag) => {
    const body = tag.replace(/^<[^\s/>]+/, "").replace(/\s*\/?>$/, "");
    return Array.from(body.matchAll(/([^\s=/>]+)(?:\s*=\s*(?:"([^"]*)"|'([^']*)'|([^\s>]+)))?/g),
      ([, key, double, single, unquoted]) => [key.toLowerCase(), double ?? single ?? unquoted]);
  });
  const missing = shells[name].filter((attribute) => {
    const [key, value] = attribute.split('="');
    return !attributes.some(([actualKey, actualValue]) => actualKey === key && (value === undefined || actualValue === value.slice(0, -1)));
  });
  if (missing.length) throw new Error(`${name} shell missing hooks: ${missing.join(", ")}`);
}

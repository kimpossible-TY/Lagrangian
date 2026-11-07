/** Display policy contains no renderer, transport, credential or storage operations. */
export function sameChatSnapshot(left, right) {
  return Boolean(
    left &&
      right &&
      left.documentID === right.documentID &&
      left.revision === right.revision &&
      JSON.stringify(left.service) === JSON.stringify(right.service),
  );
}

export function stripMathDelimiters(text) {
  if (typeof text !== "string") return "";
  return text
    .replace(/\\\[\s*([\s\S]*?)\s*(?:\\\]|$)/gu, "$1")
    .replace(/\\\(\s*([\s\S]*?)\s*(?:\\\)|$)/gu, "$1")
    .replace(/\$\$\s*([\s\S]*?)\s*(?:\$\$|$)/gu, "$1")
    .replace(
      /(^|[^\\])\$([^\s\$](?:[^\$\n]*?[^\s\$\\])?)\$(?!\d)/gu,
      (match, prefix, content, offset, fullText) => {
        const openIdx = offset + prefix.length;
        const beforeOpen = fullText.slice(0, openIdx);
        if (/(?:US|[a-zA-Z0-9])$/u.test(beforeOpen)) return match;
        if (/\d\s*[-–—]\s*$/u.test(beforeOpen)) return match;
        if (/^(?:[A-Za-z]{1,3}\s*)?\d+(?:[.,]\d+)?\s*[-–—]\s*(?:[A-Za-z]{1,3})?$/u.test(content))
          return match;
        if (/\d/u.test(fullText[offset + match.length] || "")) return match;
        return `${prefix}${content}`;
      },
    );
}

const line = (text, limit) => {
  const value = text.replace(/\s+/gu, " ").trim();
  return value.length > limit ? `${value.slice(0, limit - 1)}…` : value;
};

/** Extract the latest question and its actual answer, never synthesize a claim. */
export function conversationSummary(record) {
  const question = record.thread.findLastIndex((message) => message.role === "user");
  if (question < 0) return line(stripMathDelimiters(record.quote || ""), 140);
  const answer = record.thread.slice(question + 1).find((message) => message.role === "assistant");
  return `${line(stripMathDelimiters(record.thread[question]?.text || ""), 65)} · ${
    answer?.text
      ? `${answer.status === "completed" ? "" : "Partial: "}${line(stripMathDelimiters(answer.text), 90)}`
      : record.status === "streaming"
        ? "Thinking…"
        : record.status === "failed"
          ? "Failed · retry"
          : record.status === "interrupted"
            ? "Interrupted · retry"
            : "Ask"
  }`;
}

export class ConversationState {
  constructor() {
    this.records = new Map();
    this.generation = 0;
  }
  document(snapshot) {
    if (sameChatSnapshot(this.snapshot, snapshot)) return false;
    this.snapshot = snapshot && {
      documentID: snapshot.documentID,
      revision: snapshot.revision,
      service: snapshot.service && { ...snapshot.service },
    };
    this.records.clear();
    this.generation++;
    return true;
  }
  accept(envelope, generation = this.generation) {
    if (generation !== this.generation || !sameChatSnapshot(envelope, this.snapshot)) return false;
    for (const record of envelope.conversations) {
      const previous = this.records.get(record.conversation_id);
      if (
        previous &&
        (previous.version > record.version ||
          (previous.version === record.version &&
            (previous.sequence ?? 0) > (record.sequence ?? 0)))
      )
        continue;
      this.records.set(record.conversation_id, record);
    }
    return true;
  }
}

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

const line = (text, limit) => {
  const value = text.replace(/\s+/gu, " ").trim();
  return value.length > limit ? `${value.slice(0, limit - 1)}…` : value;
};

/** Extract the latest question and its actual answer, never synthesize a claim. */
export function conversationSummary(record) {
  const question = record.thread.findLastIndex((message) => message.role === "user");
  if (question < 0) return line(record.quote, 140);
  const answer = record.thread.slice(question + 1).find((message) => message.role === "assistant");
  return `${line(record.thread[question].text, 65)} · ${
    answer?.text
      ? `${answer.status === "completed" ? "" : "Partial: "}${line(answer.text, 90)}`
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

export type ChatSnapshot = { documentID: string; revision: string; service: unknown };
export function sameChatSnapshot(left: ChatSnapshot | null, right: ChatSnapshot | null): boolean;
export function conversationSummary(record: {
  quote: string;
  status: string;
  thread: { role: string; text: string; status: string }[];
}): string;
export class ConversationState {
  records: Map<string, any>;
  generation: number;
  snapshot: ChatSnapshot | null;
  document(snapshot: ChatSnapshot | null): boolean;
  accept(envelope: ChatSnapshot & { conversations: any[] }, generation?: number): boolean;
}

import { describe, expect, it } from "vitest";
import { decodePreviewFrame } from "./preview-frame";

describe("preview frame payload views", () => {
  it("retains a binary document without allocating another payload buffer", () => {
    const frame = new Uint8Array([110, 101, 119, 44, 0, 255, 44, 128]);
    const [kind, payload] = decodePreviewFrame(frame.buffer)!;
    expect(kind).toBe("new");
    expect(payload.buffer).toBe(frame.buffer);
    expect(payload.byteOffset).toBe(4);
    expect([...payload]).toEqual([0, 255, 44, 128]);
  });

  it.each([
    ["jump", "3 12 34"],
    ["cursor", "2 7 9"],
    ["cursor-paths", '[[["page",3]]]'],
    ["invert-colors", '"auto"'],
    ["focus-revision", "42"],
    ["focus", '{"text":"선택,본문"}'],
    ["partial-rendering", ""],
  ])("decodes only the %s payload, including UTF-8 and embedded commas", (kind, text) => {
    const frame = new TextEncoder().encode(`${kind},${text}`);
    const message = decodePreviewFrame(frame.buffer)!;
    expect(message[0]).toBe(kind);
    expect(new TextDecoder().decode(message[1])).toBe(text);
  });

  it.each(["", "new", ",payload"])("rejects a malformed envelope %j", (text) => {
    expect(decodePreviewFrame(new TextEncoder().encode(text).buffer)).toBeUndefined();
  });
});

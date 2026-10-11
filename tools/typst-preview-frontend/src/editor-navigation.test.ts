import { expect, test, vi } from "vitest";
import { EditorNavigation } from "./editor-navigation";
import type { PreviewConnection } from "./preview-connection";

const channel = "12345678-1234-1234-1234-123456789abc";
const jump = { event: "editorScrollTo", filepath: "/project/한글.typ", start: [2, 3], end: [2, 7] };
const scroll = { event: "panelScrollTo", filepath: jump.filepath, line: 2, character: 4 };
function fixture(
  query = `?tinymist-editor=${channel}&tinymist-editor-control=${encodeURIComponent(`https://forwarded.example/editor/${channel}?token=keep`)}`,
) {
  let callbacks: ConstructorParameters<typeof PreviewConnection>[1];
  const socket = { readyState: 1, send: vi.fn() };
  const dispose = vi.fn();
  const scrollPanel = vi.fn();
  const connect = vi.fn((_url, handlers) => {
    callbacks = handlers;
    handlers.opened(socket);
    return { dispose };
  });
  const navigation = new EditorNavigation(
    { location: { href: `https://reader.example/${query}` } } as Window,
    scrollPanel,
    connect,
  );
  return {
    navigation,
    socket,
    dispose,
    scrollPanel,
    connect,
    message: (value: unknown) =>
      callbacks.message(new TextEncoder().encode(JSON.stringify(value)).buffer, socket as any),
  };
}

test("desktop readers reuse both upstream control events and preserve tunnel authentication", () => {
  const f = fixture();
  expect(f.navigation.enabled).toBe(true);
  expect(f.connect.mock.calls[0][0]).toBe(`wss://forwarded.example/editor/${channel}?token=keep`);
  expect(f.navigation.reveal({ ...jump, excerpt: "private source" })).toBe(true);
  expect(JSON.parse(f.socket.send.mock.calls[0][0])).toEqual(jump);
  f.message(scroll);
  expect(f.scrollPanel).toHaveBeenCalledExactlyOnceWith(scroll);
  f.navigation.dispose();
  expect(f.dispose).toHaveBeenCalledOnce();
  expect(f.navigation.reveal(jump)).toBe(false);
});

test.each([
  "",
  `?tinymist-editor=${channel}`,
  "?tinymist-editor=invalid&tinymist-editor-control=http://localhost/editor/invalid",
])("ordinary or incomplete reader URL %s creates no control connection", (query) => {
  const f = fixture(query);
  expect(f.navigation.enabled).toBe(false);
  expect(f.connect).not.toHaveBeenCalled();
  expect(f.navigation.reveal(jump)).toBe(false);
});

test("malformed or memory-file events and stale/unmapped responses cannot navigate", () => {
  const f = fixture();
  for (const value of [
    { status: "stale" },
    { ...jump, start: [-1, 0] },
    { ...jump, end: null },
    { ...jump, event: "syncMemoryFiles" },
  ]) {
    expect(f.navigation.reveal(value)).toBe(false);
  }
  f.message({ event: "syncMemoryFiles", files: {} });
  f.message({ ...scroll, character: NaN });
  expect(f.scrollPanel).not.toHaveBeenCalled();
  expect(f.socket.send).not.toHaveBeenCalled();
  f.socket.readyState = 3;
  expect(f.navigation.reveal(jump)).toBe(false);
});

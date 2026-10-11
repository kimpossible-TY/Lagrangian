import { expect, test, vi } from "vitest";
import { EditorNavigation } from "./editor-navigation";

const channel = "12345678-1234-1234-1234-123456789abc";
const hit = {
  status: "selected",
  filepath: "/project/한글.typ",
  line: 3,
  column: 7,
  text_selected: false,
};
function fixture(embedded: boolean, query = `?tinymist-editor=${channel}`) {
  const postMessage = vi.fn();
  const host = { location: { href: `http://localhost:23625/${query}` }, parent: { postMessage } };
  if (!embedded) host.parent = host as any;
  return { bridge: new EditorNavigation(host as any), postMessage };
}

test("only an opted-in embedded viewer sends its own successful click coordinates", async () => {
  const { bridge, postMessage } = fixture(true);
  expect(bridge.enabled).toBe(true);
  expect(await bridge.reveal({ ...hit, excerpt: "private source" } as any)).toBe(true);
  expect(postMessage).toHaveBeenCalledWith(
    { type: "flowSourceLocation", channel, filepath: hit.filepath, line: 3, column: 7 },
    "*",
  );
});

test.each(["stale", "unmapped", "not_ready", "error"])("%s never navigates", async (status) => {
  const { bridge, postMessage } = fixture(true);
  expect(await bridge.reveal({ ...hit, status })).toBe(false);
  expect(postMessage).not.toHaveBeenCalled();
});

test("mobile, external browser, text selection and malformed coordinates never navigate", async () => {
  expect(await fixture(false).bridge.reveal(hit)).toBe(false);
  expect(await fixture(true, "").bridge.reveal(hit)).toBe(false);
  expect(await fixture(true, "?tinymist-editor=invalid").bridge.reveal(hit)).toBe(false);
  for (const change of [
    { text_selected: true },
    { line: 0 },
    { column: NaN },
    { column: undefined },
  ]) {
    expect(await fixture(true).bridge.reveal({ ...hit, ...change })).toBe(false);
  }
});

test("VS Code-opened external readers send a bounded callback and report expired sessions", async () => {
  const send = vi.fn().mockResolvedValue({ ok: true });
  const host: any = {
    location: {
      href: `http://localhost:23625/?tinymist-editor=${channel}&tinymist-editor-callback=${encodeURIComponent(`http://localhost:1234/source/${channel}`)}`,
    },
  };
  host.parent = host;
  const bridge = new EditorNavigation(host, send);
  expect(bridge.enabled).toBe(true);
  expect(await bridge.reveal(hit)).toBe(true);
  const [url, options] = send.mock.calls[0];
  expect(url).toBe(`http://localhost:1234/source/${channel}`);
  expect(JSON.parse(options.body)).toEqual({
    type: "flowSourceLocation",
    channel,
    filepath: hit.filepath,
    line: 3,
    column: 7,
  });
  send.mockRejectedValue(new Error("session closed"));
  expect(await bridge.reveal(hit)).toBe(false);
});

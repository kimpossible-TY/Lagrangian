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

test("only an opted-in embedded viewer sends its own successful click coordinates", () => {
  const { bridge, postMessage } = fixture(true);
  expect(bridge.enabled).toBe(true);
  expect(bridge.reveal({ ...hit, excerpt: "private source" } as any)).toBe(true);
  expect(postMessage).toHaveBeenCalledWith(
    { type: "flowSourceLocation", channel, filepath: hit.filepath, line: 3, column: 7 },
    "*",
  );
});

test.each(["stale", "unmapped", "not_ready", "error"])("%s never navigates", (status) => {
  const { bridge, postMessage } = fixture(true);
  expect(bridge.reveal({ ...hit, status })).toBe(false);
  expect(postMessage).not.toHaveBeenCalled();
});

test("mobile, external browser, text selection and malformed coordinates never navigate", () => {
  expect(fixture(false).bridge.reveal(hit)).toBe(false);
  expect(fixture(true, "").bridge.reveal(hit)).toBe(false);
  expect(fixture(true, "?tinymist-editor=invalid").bridge.reveal(hit)).toBe(false);
  for (const change of [
    { text_selected: true },
    { line: 0 },
    { column: NaN },
    { column: undefined },
  ]) {
    expect(fixture(true).bridge.reveal({ ...hit, ...change })).toBe(false);
  }
});

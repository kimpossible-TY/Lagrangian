import { describe, expect, it, vi } from "vitest";
import {
  DocumentThemeController,
  themeWebSocketUrl,
  captureReadingState,
  createConnectionQueue,
  ThemeReadingState,
} from "./document-theme";
import { ChangeLocationQueue } from "../navigation/change-location";

class Device extends EventTarget {
  constructor(public matches: boolean) {
    super();
  }
  change(dark: boolean) {
    this.matches = dark;
    this.dispatchEvent(new Event("change"));
  }
}

function fixture(dark = false) {
  const device = new Device(dark);
  const selections = new EventTarget();
  const onTheme = vi.fn();
  let held = false;
  const controller = new DocumentThemeController(
    device as any,
    selections as any,
    () => held,
    onTheme,
  );
  const select = (value: boolean) => {
    held = value;
    selections.dispatchEvent(new Event("selectionchange"));
  };
  return { device, selections, onTheme, controller, select };
}

describe("native document theme", () => {
  it.each([false, true])("detects initial device appearance (%s) and follows changes", (dark) => {
    const { device, onTheme } = fixture(dark);
    expect(onTheme.mock.calls).toEqual([[dark ? "dark" : "light"]]);
    device.change(!dark);
    expect(onTheme).toHaveBeenLastCalledWith(dark ? "light" : "dark");
    device.change(!dark);
    expect(onTheme).toHaveBeenCalledTimes(2);
  });

  it("keeps an override and resumes the current device appearance in System", () => {
    const { device, onTheme, controller } = fixture(true);
    controller.setPreference("light");
    device.change(false);
    device.change(true);
    expect(onTheme.mock.calls).toEqual([["dark"], ["light"]]);
    controller.setPreference("system");
    expect(onTheme).toHaveBeenLastCalledWith("dark");
  });

  it("holds the selected SVG and applies only the latest request when selection collapses", () => {
    const { device, onTheme, controller, select } = fixture();
    select(true);
    device.change(true);
    controller.setPreference("light");
    controller.setPreference("dark");
    expect(onTheme.mock.calls).toEqual([["light"]]);
    select(false);
    expect(onTheme.mock.calls).toEqual([["light"], ["dark"]]);
  });

  it("does not interfere with another viewer", () => {
    const first = fixture();
    const second = fixture();
    first.controller.setPreference("dark");
    expect(first.onTheme).toHaveBeenLastCalledWith("dark");
    expect(second.onTheme.mock.calls).toEqual([["light"]]);
  });

  it("removes listeners on disposal", () => {
    const { device, selections, controller, onTheme } = fixture();
    const deviceRemove = vi.spyOn(device, "removeEventListener");
    const selectionRemove = vi.spyOn(selections, "removeEventListener");
    controller.dispose();
    device.change(true);
    selections.dispatchEvent(new Event("selectionchange"));
    controller.setPreference("dark");
    expect(onTheme).toHaveBeenCalledOnce();
    expect(deviceRemove).toHaveBeenCalledOnce();
    expect(selectionRemove).toHaveBeenCalledOnce();
  });

  it("uses the same HTTPS host and port for both WebSocket variants", () => {
    const url = "wss://preview.example.ts.net:23625/";
    expect(themeWebSocketUrl(url, "light")).toBe(url + "_theme/light");
    expect(themeWebSocketUrl(url, "dark")).toBe(url + "_theme/dark");
  });

  it("captures reading state without changing the document", () => {
    const container = { scrollTop: 31415, scrollLeft: 42 };
    const context = { currentScaleRatio: 1.75, partialRenderPage: 12 };
    expect(captureReadingState(container, context)).toEqual({
      top: 31415,
      left: 42,
      scale: 1.75,
      page: 12,
    });
    expect(container.scrollTop).toBe(31415);
  });

  it("restores the saved edit when themes change before the first completed render", () => {
    const state = new ThemeReadingState();
    const container = { scrollTop: 0, scrollLeft: 0 };
    // A renderer may already have merged its module, but not displayed the document.
    for (let transition = 0; transition < 3; transition++) {
      const context = { currentScaleRatio: 1, partialRenderPage: 0, moduleInitialized: true };
      const reading = state.capture(container, context);
      expect(reading).toBeUndefined();
      const changes = new ChangeLocationQueue(Boolean(reading));
      changes.queue([302, 524, 750], true);
      expect(changes.afterRender(5000, -Infinity)?.location).toEqual([302, 524, 750]);
    }
  });

  it("keeps the last displayed position through multiple unfinished theme replacements", () => {
    const state = new ThemeReadingState();
    const first = { currentScaleRatio: 1.75, partialRenderPage: 12 };
    const container = { scrollTop: 31415, scrollLeft: 42 };
    state.didRender(first);
    const reading = state.capture(container, first);
    expect(reading).toEqual({ top: 31415, left: 42, scale: 1.75, page: 12 });

    for (let transition = 0; transition < 3; transition++) {
      const pending = { currentScaleRatio: 1, partialRenderPage: 0 };
      const retained = state.capture({ scrollTop: 0, scrollLeft: 0 }, pending);
      expect(retained).toEqual(reading);
      const changes = new ChangeLocationQueue(Boolean(retained));
      changes.queue([302, 524, 750], true);
      expect(changes.afterRender(5000, -Infinity)).toBeUndefined();
      changes.queue([303, 0, 50]);
      expect(changes.afterRender(6000, -Infinity)?.location).toEqual([303, 0, 50]);
    }

    const final = { currentScaleRatio: 2, partialRenderPage: 14 };
    state.didRender(final);
    expect(state.capture({ scrollTop: 42000, scrollLeft: 0 }, final)).toEqual({
      top: 42000,
      left: 0,
      scale: 2,
      page: 14,
    });
  });

  it("coalesces queued requests and disposes the old connection exactly once", async () => {
    const disposers = [vi.fn(), vi.fn()];
    const connect = vi.fn().mockResolvedValueOnce(disposers[0]).mockResolvedValueOnce(disposers[1]);
    const capture = vi.fn((x: string) => x);
    const next = createConnectionQueue(connect, capture);
    await next("light");
    next("dark");
    next("light");
    await next("dark");
    expect(connect.mock.calls).toEqual([["light"], ["dark"]]);
    expect(capture.mock.calls).toEqual([["light"], ["dark"]]);
    expect(disposers[0]).toHaveBeenCalledOnce();
    expect(disposers[1]).not.toHaveBeenCalled();
  });

  it("serializes a new request while renderer initialization is in flight", async () => {
    let finish!: (dispose: () => void) => void;
    const dispose = vi.fn();
    const connect = vi
      .fn()
      .mockImplementationOnce(
        () =>
          new Promise<() => void>((resolve) => {
            finish = resolve;
          }),
      )
      .mockResolvedValueOnce(() => {});
    const next = createConnectionQueue(connect, (x: string) => x);
    const first = next("light");
    await Promise.resolve();
    await Promise.resolve();
    const second = next("dark");
    expect(connect).toHaveBeenCalledOnce();
    finish(dispose);
    await first;
    await second;
    expect(connect.mock.calls).toEqual([["light"], ["dark"]]);
    expect(dispose).toHaveBeenCalledOnce();
  });
});

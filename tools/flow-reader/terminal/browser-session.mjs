// Own the dedicated persistent browser without changing the user's Chrome profile.
import { access, mkdir } from "node:fs/promises";
import { constants } from "node:fs";
import path from "node:path";
import { pathToFileURL } from "node:url";
import { profileDefaults } from "./options.mjs";

export async function loadPlaywright(options) {
  const module =
    options["playwright-module"] || process.env.FLOW_READER_PLAYWRIGHT_MODULE || "playwright";
  try {
    return await import(
      module.startsWith(".") || path.isAbsolute(module)
        ? pathToFileURL(path.resolve(module)).href
        : module
    );
  } catch (error) {
    throw new Error(
      `Playwright is required. Set --playwright-module or FLOW_READER_PLAYWRIGHT_MODULE to an installed playwright/index.mjs. ${error.message}`,
    );
  }
}

export async function browserOptions(options) {
  if (options["browser-executable"]) {
    await access(options["browser-executable"], constants.X_OK);
    return { executablePath: options["browser-executable"] };
  }
  return { channel: "chrome" };
}

export async function openReader(options, viewport = { width: 900, height: 702 }) {
  const { chromium } = await loadPlaywright(options);
  const profile = path.resolve(options.profile || profileDefaults(options).profile);
  await mkdir(profile, { recursive: true, mode: 0o700 });
  const context = await chromium.launchPersistentContext(profile, {
    ...(await browserOptions(options)),
    headless: true,
    viewport,
    deviceScaleFactor: 1,
    locale: "ko-KR",
    acceptDownloads: false,
  });
  // An external link must not leave an unobserved browser running behind the pane.
  context.on("page", (page) => {
    if (page !== context.pages()[0]) page.close().catch(() => {});
  });
  const page = context.pages()[0] || (await context.newPage());
  return { context, page, close: () => context.close() };
}

export async function waitForReader(page, url, options = {}) {
  const terminalURL = new URL(url);
  terminalURL.searchParams.set("terminal", "1");
  if (options["editor-server"])
    terminalURL.searchParams.set("terminalEditorServer", options["editor-server"]);
  if (options["editor-attachment"])
    terminalURL.searchParams.set("terminalEditorAttachment", options["editor-attachment"]);
  await page.goto(terminalURL.href, { waitUntil: "domcontentloaded", timeout: 60000 });
  if (options["editor-server"]) {
    const state = await (await page.request.get(new URL("api/state", terminalURL).href)).json();
    if (options["editor-attachment"]) {
      const response = await page.request.post(new URL("api/editor-attachment", terminalURL).href, {
        data: { token: options["editor-attachment"] },
      });
      if (state.editorAttachments !== 1 || !response.ok() || !(await response.json()).connected)
        throw new Error(
          "The shared HTML Reader editor attachment expired. Reopen the Reader view.",
        );
    } else if (state.editorServer !== options["editor-server"])
      throw new Error(
        "The Reader is not connected to this Neovim server. Restart it with matching --editor-server before enabling source highlights.",
      );
  }
  await page.waitForFunction(
    () => {
      const article = document.querySelector("#reader-document");
      return (
        article?.querySelector("[data-reader-key]") && article.getAttribute("aria-busy") === "false"
      );
    },
    null,
    { timeout: 120000 },
  );
  await page.evaluate(() => document.fonts.ready);
  // Give asynchronous math preparation a chance to paint before the first frame.
  await page.waitForTimeout(150);
}

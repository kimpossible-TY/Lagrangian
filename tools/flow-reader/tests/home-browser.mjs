import assert from "node:assert/strict";
import { spawn } from "node:child_process";
import { once } from "node:events";
import { createInterface } from "node:readline";
import { fileURLToPath } from "node:url";
import { mkdir } from "node:fs/promises";

const { chromium } = await import(process.env.FLOW_READER_PLAYWRIGHT_MODULE || "playwright");
const fixture = spawn(
  process.env.PYTHON || "python3",
  ["-B", fileURLToPath(new URL("./home_fixture.py", import.meta.url))],
  { stdio: ["ignore", "pipe", "inherit"] },
);
const lines = createInterface({ input: fixture.stdout });
const { url, token, proxyURL } = await new Promise((resolve, reject) => {
  lines.once("line", (line) => resolve(JSON.parse(line)));
  fixture.once("exit", (code) => reject(new Error(`Fixture exited ${code}`)));
});
let browser,
  checks = 0;
const check = (name, value) => {
  assert.ok(value, name);
  checks++;
};
const control = async (body) => {
  const response = await fetch(url + "fixture-control", {
    method: "POST",
    headers: { "Content-Type": "application/json", "X-Fixture-Token": token },
    body: JSON.stringify(body),
  });
  assert.ok(response.ok);
  return response.json();
};
const artifacts = process.env.FLOW_HOME_ARTIFACTS || "/tmp/lagrangian-home-artifacts";
try {
  browser = await chromium.launch({
    headless: true,
    ...(process.env.CHROME_BIN ? { executablePath: process.env.CHROME_BIN } : {}),
  });
  const context = await browser.newContext({
    viewport: { width: 1360, height: 960 },
    reducedMotion: "reduce",
  });
  const page = await context.newPage(),
    errors = [];
  await context.route("https://auth.openai.com/**", (route) =>
    route.fulfill({ contentType: "text/html", body: "<title>OpenAI login fixture</title>" }),
  );
  page.on("pageerror", (error) => errors.push(error.message));
  await page.goto(url);
  await page.locator(".document-card").first().waitFor();
  check("configured inventory only", (await page.locator(".document-card").count()) === 2);
  check(
    "no OAuth or model request on load",
    JSON.stringify(await control({})) === JSON.stringify({ authCalls: [], modelCalls: 0 }),
  );
  const focusContext = await browser.newContext({ viewport: { width: 1360, height: 960 } });
  const focusPage = await focusContext.newPage();
  focusPage.on("pageerror", (error) => errors.push(error.message));
  await focusPage.clock.install();
  await focusPage.goto(url);
  const pollingLink = focusPage.getByRole("link", {
    name: "편미분방정식 · HTML Reader",
    exact: true,
  });
  await pollingLink.waitFor();
  await pollingLink.focus();
  const originalLink = await pollingLink.elementHandle();
  await control({ mode: "compiling" });
  const polledDocuments = focusPage.waitForResponse(
    (response) =>
      response.url() === url + "api/home/documents" && response.request().method() === "GET",
  );
  await focusPage.clock.fastForward(16000);
  await (await polledDocuments).finished();
  await focusPage.locator('.document-status[data-state="compiling"]').waitFor();
  check(
    "15-second polling preserves focused Reader link identity while updating status",
    await focusPage.evaluate(
      (link) =>
        link.isConnected &&
        document.activeElement === link &&
        link === document.querySelector(".reader-link"),
      originalLink,
    ),
  );
  await control({ mode: "empty" });
  const removedDocuments = focusPage.waitForResponse(
    (response) =>
      response.url() === url + "api/home/documents" && response.request().method() === "GET",
  );
  await focusPage.clock.fastForward(16000);
  await (await removedDocuments).finished();
  await focusPage.waitForFunction(() => document.querySelectorAll(".document-card").length === 0);
  check(
    "Removed focused document returns focus to the document section",
    await focusPage.evaluate(() => document.activeElement === document.getElementById("documents")),
  );
  await focusContext.close();
  await control({ mode: "ready" });
  const readerLogo = await page.locator(".reader-logo-base").getAttribute("d");
  check("actual Reader logo path", readerLogo.startsWith("M31 29 C48 45"));
  check(
    "desktop two-column composition",
    await page.locator(".layout").evaluate((el) => getComputedStyle(el).display === "grid"),
  );
  check(
    "host has no Service Worker",
    await page.evaluate(
      async () => (await navigator.serviceWorker.getRegistrations()).length === 0,
    ),
  );
  await page.locator("#document-search").fill("기하");
  check("title search", (await page.locator(".document-card").count()) === 1);
  await page.locator("#document-search").fill("missing");
  check(
    "search empty state",
    (await page.locator("#inventory-message").textContent()).includes("검색 결과"),
  );
  await page.locator("#document-search").fill("");
  await page.keyboard.press("Tab");
  check(
    "keyboard focus has visible outline",
    await page.evaluate(() => getComputedStyle(document.activeElement).outlineStyle !== "none"),
  );
  await mkdir(artifacts, { recursive: true });
  await page.screenshot({ path: `${artifacts}/desktop.png`, fullPage: true });
  await page.locator("#reader-theme").selectOption("dark");
  check(
    "Reader theme preference reused",
    (await page.locator("html").getAttribute("data-theme")) === "dark",
  );
  await page.screenshot({ path: `${artifacts}/dark.png`, fullPage: true });
  await page.locator("#reader-theme").selectOption("light");
  for (const operation of ["login", "logout"]) {
    if (operation === "logout") await control({ signedIn: true });
    const retainedContext = await browser.newContext();
    await retainedContext.route("https://auth.openai.com/**", (route) =>
      route.fulfill({ contentType: "text/html", body: "<title>OpenAI login fixture</title>" }),
    );
    const retainedPage = await retainedContext.newPage();
    await retainedPage.goto(url);
    await retainedPage.locator("#host-proof").fill("fixture-host-proof");
    await retainedPage.locator("#unlock button").click();
    await retainedPage.locator("#unlock").waitFor({ state: "hidden" });
    const managementCookie = (await retainedContext.cookies()).find(
      (cookie) => cookie.name === "ReaderHomeAdmin",
    ).value;
    await retainedPage.reload();
    await retainedPage.locator(`#${operation}`).waitFor({ state: "visible" });
    check(
      `${operation}: reload retains the management cookie`,
      (await retainedContext.cookies()).some(
        (cookie) => cookie.name === "ReaderHomeAdmin" && cookie.value === managementCookie,
      ),
    );
    const mutation = retainedPage.waitForResponse(
      (response) =>
        response.url() === url + "api/home/account" && response.request().method() === "POST",
    );
    await retainedPage.locator(`#${operation}`).click();
    const response = await mutation;
    const result = await response.json();
    check(
      `${operation}: first action after reload succeeds with OAuth-only CSRF`,
      response.status() === 200 &&
        !result.management &&
        !response.request().headers()["x-reader-host-capability"] &&
        Boolean(response.request().headers()["x-reader-csrf"]),
    );
    if (operation === "login") await retainedPage.waitForURL("https://auth.openai.com/**");
    else
      await retainedPage.waitForFunction(
        () => document.querySelector("#account-label").textContent === "연결되지 않음",
      );
    await retainedContext.close();
  }
  const loginsBefore = (await control({})).authCalls.filter((v) => v === "login").length;
  await context.route("https://auth.openai.com/**", (route) =>
    route.fulfill({
      contentType: "text/html",
      body: "<title>OpenAI authorize fixture</title><p>Local authorize fixture</p>",
    }),
  );
  await page.locator("#login").waitFor({ state: "visible" });
  const loginRequest = page.waitForRequest(
    (request) => request.url() === url + "api/home/account" && request.method() === "POST",
  );
  await page.locator("#login").click();
  await page.waitForURL("https://auth.openai.com/**");
  const startedLogin = await loginRequest;
  check(
    "one local click navigates directly to OpenAI with CSRF and no host proof",
    !startedLogin.headers()["x-reader-host-capability"] &&
      Boolean(startedLogin.headers()["x-reader-csrf"]),
  );
  check(
    "explicit login only once",
    (await control({})).authCalls.filter((v) => v === "login").length === loginsBefore + 1,
  );
  await page.goBack();
  await page.waitForFunction(
    () => document.querySelector("#account-label").textContent === "로그인 대기 중",
  );
  check("cancel still needs management unlock", await page.locator("#cancel").isHidden());
  await page.locator("#host-proof").fill("fixture-host-proof");
  await page.locator("#unlock button").click();
  await page.locator("#cancel").waitFor({ state: "visible" });
  check(
    "host proof stays out of storage",
    await page.evaluate(
      () => !JSON.stringify({ ...localStorage, ...sessionStorage }).includes("fixture-host-proof"),
    ),
  );
  await control({ interrupted: true });
  await page.locator("#refresh").click();
  await page.locator("#login").waitFor({ state: "visible" });
  check(
    "interrupted login feedback",
    (await page.locator("#account-notice").textContent()).includes("expired"),
  );
  await page.locator("#login").click();
  await page.waitForURL("https://auth.openai.com/**");
  await page.goBack();
  await page.locator("#host-proof").fill("fixture-host-proof");
  await page.locator("#unlock button").click();
  await page.locator("#cancel").waitFor({ state: "visible" });
  await page.locator("#cancel").click();
  await page.locator("#login").waitFor({ state: "visible" });
  await control({ signedIn: true });
  await page.locator("#refresh").click();
  await page.waitForFunction(
    () => document.querySelector("#account-label").textContent === "연결됨",
  );
  check("sign-in rotates authority", await page.locator("#unlock").isVisible());
  await page.reload();
  await page.locator("#logout").waitFor({ state: "visible" });
  await control({ catalogFailure: true });
  await page.locator("#models").click();
  await page.waitForFunction(() =>
    document.querySelector("#model-notice").textContent.includes("다시 로그인"),
  );
  check(
    "catalog failure shows reauthentication",
    (await page.locator("#model-list li").count()) === 0,
  );
  const remoteContext = await browser.newContext({ viewport: { width: 1360, height: 960 } });
  await remoteContext.route("https://home.example:8443/**", async (route) => {
    const original = new URL(route.request().url());
    const response = await route.fetch({
      url: proxyURL + original.pathname.slice(1) + original.search,
      headers: { ...route.request().headers(), Host: "home.example:8443" },
    });
    await route.fulfill({ response });
  });
  const remote = await remoteContext.newPage();
  await remote.goto("https://home.example:8443/");
  await remote.waitForFunction(
    () => document.querySelector("#account-label").textContent === "연결됨",
  );
  check(
    "remote account view has no Mac management controls",
    (await remote.locator("#unlock").isHidden()) &&
      (await remote.locator("#account-controls").isHidden()),
  );
  check(
    "remote account and inventory reveal no registration identity or loopback destination",
    await remote.evaluate(
      () =>
        !document.body.textContent.includes("private@example") &&
        ![...document.querySelectorAll("a[href]")].some((a) => a.href.includes("127.0.0.1")),
    ),
  );
  const remoteProof = await remote.evaluate(async () => {
    const response = await fetch("/api/home/session", {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: "{}",
    });
    return response.json();
  });
  check("HTTPS proxy session remains read-only", remoteProof.management === false);
  check(
    "remote mutation denied with its own valid CSRF",
    await remote.evaluate(
      async (csrf) =>
        (
          await fetch("/api/home/account", {
            method: "POST",
            headers: { "Content-Type": "application/json", "X-Reader-CSRF": csrf },
            body: JSON.stringify({ operation: "logout" }),
          })
        ).status === 403,
      remoteProof.csrf,
    ),
  );
  await remote.screenshot({ path: `${artifacts}/remote-desktop.png`, fullPage: true });
  await remoteContext.close();
  const second = await context.newPage();
  await second.goto(url);
  await second.waitForFunction(
    () => document.querySelector("#account-label").textContent === "연결됨",
  );
  let releaseOld;
  let capturedOld;
  const oldReady = new Promise((resolve) => {
    capturedOld = resolve;
  });
  const oldGate = new Promise((resolve) => {
    releaseOld = resolve;
  });
  let interceptOld = true;
  await page.route("**/api/home/account", async (route) => {
    if (!interceptOld || route.request().method() !== "GET") return route.continue();
    interceptOld = false;
    const response = await route.fetch();
    const body = await response.body();
    capturedOld();
    await oldGate;
    await route.fulfill({ response, body }).catch(() => {});
  });
  await page.locator("#refresh").click();
  await oldReady;
  const logoutRequest = page.waitForRequest(
    (request) => request.url() === url + "api/home/account" && request.method() === "POST",
  );
  await page.locator("#logout").click();
  check(
    "logout needs no host proof after credential rotation",
    !(await logoutRequest).headers()["x-reader-host-capability"],
  );
  await page.waitForFunction(
    () => document.querySelector("#account-label").textContent === "연결되지 않음",
  );
  await second.waitForFunction(
    () => document.querySelector("#account-label").textContent === "연결되지 않음",
  );
  releaseOld();
  await page.waitForTimeout(50);
  check(
    "late signed-in response cannot repaint logout",
    (await page.locator("#account-label").textContent()) === "연결되지 않음",
  );
  await page.unroute("**/api/home/account");
  check(
    "honest unconfirmed revocation",
    (await page.locator("#account-notice").textContent()).includes("not confirmed"),
  );
  await second.close();
  await control({ mode: "timeout" });
  await page.locator("#refresh").click();
  await page.waitForFunction(
    () => document.querySelector(".document-status").dataset.state === "stale",
  );
  check(
    "stale observation labelled",
    (await page.locator(".document-status").first().textContent()).includes("이전"),
  );
  await control({ mode: "empty" });
  await page.locator("#refresh").click();
  await page.waitForFunction(() => document.querySelectorAll(".document-card").length === 0);
  check(
    "empty configured inventory",
    (await page.locator("#inventory-message").textContent()).includes("등록된 문서"),
  );
  await control({ mode: "error" });
  await page.locator("#refresh").click();
  await page.waitForFunction(() =>
    document
      .querySelector("#inventory-message")
      .textContent.includes("문서 설정을 읽지 못했습니다"),
  );
  check(
    "private configuration error redacted",
    !(await page.textContent("body")).includes("/private/source"),
  );
  await page.screenshot({ path: `${artifacts}/error-empty.png`, fullPage: true });
  await control({ mode: "ready" });
  await page.locator("#refresh").click();
  await page.locator(".document-card").first().waitFor();
  await page.setViewportSize({ width: 390, height: 844 });
  check(
    "mobile no horizontal overflow",
    await page.evaluate(() => document.documentElement.scrollWidth <= innerWidth),
  );
  check(
    "mobile single column",
    await page.locator(".layout").evaluate((el) => getComputedStyle(el).display === "block"),
  );
  check(
    "account follows documents",
    await page
      .locator("#connection")
      .evaluate((el) => el.offsetTop > document.querySelector("#documents").offsetTop),
  );
  await page.screenshot({ path: `${artifacts}/mobile.png`, fullPage: true });
  const touchContext = await browser.newContext({
    viewport: { width: 390, height: 844 },
    isMobile: true,
    hasTouch: true,
  });
  const touch = await touchContext.newPage();
  await touch.goto(url);
  await touch.locator(".document-card").first().waitFor();
  await touch.locator("#document-search").tap();
  await touch.locator("#document-search").fill("기하");
  check("touch title search", (await touch.locator(".document-card").count()) === 1);
  await touch.locator("#document-search").fill("");
  // Inventory changes can remove destinations. Measure current links together
  // after the response/rendering frame; retain 44px targets on both axes.
  const refreshedDocuments = touch.waitForResponse(
    (response) =>
      response.url() === url + "api/home/documents" && response.request().method() === "GET",
  );
  await touch.locator("#refresh").tap();
  await (await refreshedDocuments).finished();
  await touch.evaluate(() => new Promise(requestAnimationFrame));
  const touchTargets = await touch.evaluate(() =>
    [...document.querySelectorAll(".reader-link")].map((el) => {
      const bounds = el.getBoundingClientRect();
      return { connected: el.isConnected, width: bounds.width, height: bounds.height };
    }),
  );
  check(
    "touch reader links have usable targets",
    touchTargets.length > 0 &&
      touchTargets.every(
        (target) => target.connected && target.width >= 43.9 && target.height >= 43.9,
      ),
  );
  await touch.evaluate(() => {
    document.activeElement?.blur();
    getSelection()?.removeAllRanges();
    window.scrollTo(0, 0);
  });
  await touch.screenshot({ path: `${artifacts}/mobile.png`, fullPage: true });
  await touchContext.close();
  await context.route("https://html.example/**", (route) =>
    route.fulfill({
      contentType: "text/html",
      body: "<title>Reader navigation fixture</title><p>Existing document origin</p>",
    }),
  );
  await page.getByRole("link", { name: "편미분방정식 · HTML Reader" }).click();
  await page.waitForURL("https://html.example/");
  await page.goBack();
  await page.locator(".document-card").first().waitFor();
  check("direct Reader navigation and history", page.url() === url);
  await context.setOffline(true);
  await page.locator("#refresh").click();
  await page.waitForFunction(
    () => document.querySelector("#account-label").textContent === "상태 미확인",
  );
  check(
    "offline account never claims current connection",
    await page.locator("#account-controls").isHidden(),
  );
  await context.setOffline(false);
  const lifecycle = await context.newPage();
  await lifecycle.goto(url);
  await lifecycle.locator(".document-card").first().waitFor();
  let requestsAfterHide = 0;
  await lifecycle.route("**/api/home/**", (route) => {
    requestsAfterHide++;
    return route.continue();
  });
  await lifecycle.evaluate(() => {
    Object.defineProperty(document, "hidden", { configurable: true, get: () => true });
    document.dispatchEvent(new Event("visibilitychange"));
    document.querySelector("#refresh").click();
  });
  await lifecycle.waitForTimeout(50);
  check("hidden page does not poll", requestsAfterHide === 0);
  await lifecycle.evaluate(() => {
    window.dispatchEvent(new Event("pagehide"));
    Object.defineProperty(document, "hidden", { configurable: true, get: () => false });
    document.querySelector("#refresh").click();
  });
  await lifecycle.waitForTimeout(50);
  check("disposed page does not request or replay actions", requestsAfterHide === 0);
  await lifecycle.close();
  check("no browser errors", errors.length === 0);
  console.log(JSON.stringify({ checks, artifacts, errors }));
} finally {
  if (browser) await browser.close();
  fixture.kill("SIGTERM");
  await once(fixture, "exit");
  lines.close();
}

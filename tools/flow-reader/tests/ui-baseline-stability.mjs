// Require a second matching frame; a bounded failure is evidence, not a baseline.
export async function stableScreenshot(take, { attempts = 10, interval = 200, wait = (ms) => new Promise((resolve) => setTimeout(resolve, ms)) } = {}) {
  let previous = await take();
  for (let retryCount = 1; retryCount < attempts; retryCount++) {
    await wait(interval);
    const current = await take();
    if (current.equals(previous)) return { image: current, retryCount };
    previous = current;
  }
  return { image: previous, retryCount: attempts - 1, unstable: true };
}

import { composeCanvas } from "./canvas-layout.js";

globalThis.onmessage = ({ data: { id, input } }) => {
  try {
    globalThis.postMessage({ id, plan: composeCanvas(...input) });
  } catch {
    globalThis.postMessage({ id, error: true });
  }
};

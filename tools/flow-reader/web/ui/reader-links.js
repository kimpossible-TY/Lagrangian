// Python's reader_url owns configured-origin and loopback-host policy. Both
// clients consume its normalized URLs; only guard executable link schemes here.
export function readerLink(value) {
  try {
    const url = new URL(value);
    return url.protocol === "https:" || url.protocol === "http:" ? url.href : null;
  } catch {
    return null;
  }
}

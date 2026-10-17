// Test-only bootstrap runs before the Reader module. Seed a conflicting saved
// position with the exact URL being opened, including its named target.
{
  const testKey = "flow-reader-entry-test:" + location.search;
  if (!sessionStorage.getItem(testKey)) {
    const anchor = __SEED_ANCHOR__;
    anchor.url = location.href;
    localStorage.setItem("flow-reader:" + __DOCUMENT_ID__ + ":position", JSON.stringify(anchor));
    localStorage.setItem("flow-reader:" + __DOCUMENT_ID__ + ":fontSizeV2", "18");
    document.documentElement.dataset.entrySeedKey = anchor.key;
    document.documentElement.dataset.entrySeedMode = "new";
  } else {
    document.documentElement.dataset.entrySeedMode = "reload";
  }
}

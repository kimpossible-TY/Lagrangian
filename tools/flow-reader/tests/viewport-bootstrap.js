// Disposable loopback fixture only: exercise both path and document preferences.
{
  const testKey = "flow-reader-viewport-test:" + location.search;
  if (!sessionStorage.getItem(testKey)) {
    const legacy = new URL(location.href).searchParams.get("legacy") === "1";
    for (const key of ["flow-reader:" + location.pathname, "flow-reader:" + __DOCUMENT_ID__]) {
      localStorage.removeItem(key + ":fontSizeV2");
      if (legacy) localStorage.setItem(key + ":fontSize", "20");
      else localStorage.removeItem(key + ":fontSize");
    }
  }
}

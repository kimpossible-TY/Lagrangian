let pending;

export function loadMathJax() {
  if (pending) return pending;
  pending = new Promise((resolve, reject) => {
    const assets = new URL("../../vendor/mathjax-4.1.3/", import.meta.url).href;
    globalThis.MathJax = {
      mml: { allowHtmlInTokenNodes: true },
      loader: { paths: { mathjax: assets + "mathjax" }, load: ["a11y/assistive-mml"] },
      output: {
        displayOverflow: "linebreak",
        linebreaks: { inline: true, width: "100%", lineleading: 0.3 },
        font: "mathjax-newcm",
        fontPath: assets + "%%FONT%%",
      },
      chtml: {
        fontURL: assets + "mathjax-newcm/chtml/woff2",
        dynamicPrefix: assets + "mathjax-newcm/chtml/dynamic",
      },
      options: {
        enableMenu: false,
        enableEnrichment: false,
        enableSpeech: false,
        enableBraille: false,
        enableExplorer: false,
        enableAssistiveMml: true,
        menuOptions: {
          settings: { enrich: false, speech: false, braille: false, assistiveMml: true },
        },
      },
      startup: { typeset: false },
    };
    const script = document.createElement("script");
    script.src = assets + "mathjax/mml-chtml.js";
    const fail = (error) => {
      script.remove();
      reject(error);
    };
    script.onload = () =>
      Promise.resolve()
        .then(() => {
          if (!globalThis.MathJax.startup?.promise)
            throw new Error("수식 조판 엔진을 시작하지 못했습니다.");
          return globalThis.MathJax.startup.promise;
        })
        .then(() => resolve(globalThis.MathJax), fail);
    script.onerror = () => fail(new Error("수식 조판 엔진을 불러오지 못했습니다."));
    document.head.append(script);
  });
  // A transient load failure can be retried without reloading the document.
  pending.catch(() => {
    pending = null;
  });
  return pending;
}

import { PreviewMode } from "typst-dom/typst-doc.mjs";
import { hasTouchSelection } from "typst-dom/touch-selection.mjs";
import {
  TypstPreviewDocument as TypstDocument,
  TypstDomHookedElement,
  TypstDomWindowElement,
} from "typst-dom/index.preview.mjs";
import {
  rendererBuildInfo,
  createTypstRenderer,
} from "@myriaddreamin/typst.ts/dist/esm/renderer.mjs";
import renderModule from "@myriaddreamin/typst-ts-renderer/pkg/typst_ts_renderer_bg.wasm?url";
// @ts-ignore
// import { RenderSession as RenderSession2 } from "@myriaddreamin/typst-ts-renderer/pkg/wasm-pack-shim.mjs";
import { RenderSession } from "@myriaddreamin/typst.ts/dist/esm/renderer.mjs";
import { Subject, Subscription, buffer, debounceTime, auditTime, fromEvent, tap } from "rxjs";
import { handleHtmlPreviewFrame } from "./html-preview";
import type { ReadingContext, ReadingState } from "./document-theme";
import { ChangeLocationQueue, parseChangeLocation, type ChangeLocation } from "./change-location";
import { focusStatusPlacement } from "./mobile-viewport";
import { SelectionActions } from "./selection-actions";
import { PreviewActivity } from "./preview-activity";
import { decodePreviewFrame } from "./preview-frame";
import { ReferenceNavigation } from "./reference-navigation";
import { EditorNavigation, type PanelScrollRequest } from "./editor-navigation";
import { PreviewConnection } from "./preview-connection";
export { PreviewMode } from "typst-dom/typst-doc.mjs";

// for debug propose
// queryObjects((window as any).TypstRenderSession);
(window as any).TypstRenderSession = RenderSession;
// (window as any).TypstRenderSessionKernel = RenderSession2;

const dec = new TextDecoder();
const NOT_AVAILABLE = "current not available";
export interface WsArgs {
  url: string;
  previewMode: PreviewMode;
  isContentPreview: boolean;
  nativeTheme?: boolean;
  onToggleTheme?: () => void;
  readingState?: ReadingState;
  onDidRender?: (context: ReadingContext) => void;
}

export async function wsMain({
  url,
  previewMode,
  isContentPreview,
  nativeTheme,
  onToggleTheme,
  readingState,
  onDidRender,
}: WsArgs) {
  if (!url) {
    const status = document.getElementById("typst-preview-status");
    if (status) status.hidden = true;
    const hookedElem = document.getElementById("typst-app");
    if (hookedElem) {
      hookedElem.innerHTML = "";
    }
    return () => {};
  }
  const windowElem = document.getElementById("typst-container")! as TypstDomWindowElement;
  const activity = new PreviewActivity();
  const updateActivity = (update: () => void) => {
    update();
    activity.refresh();
  };

  let pendingEditorScroll: PanelScrollRequest | undefined;
  let flushEditorScroll = () => {};
  const editorNavigation = new EditorNavigation(window, (request) => {
    // Keep only the latest cursor location while rendering/reconnecting.
    pendingEditorScroll = request;
    flushEditorScroll();
  });
  let disposed = false;
  let connection: PreviewConnection | undefined;
  let awaitingFullFrame = true;
  const subsribes: Subscription[] = [];
  let queueChangedLocation: ((location: ChangeLocation, resume: boolean) => void) | undefined;
  let clearChangedLocation: (() => void) | undefined;
  let focusRevision: string | undefined;
  let pendingFocusRevision: string | undefined;
  let pendingFocusDocument: string | undefined;
  let queuedFocusRevision: string | undefined;
  let queuedFocusDocument: string | undefined;
  let focusStatus: HTMLDivElement | undefined;
  let focusEnabled = false;
  let selectionActions: SelectionActions | undefined;
  const positionFocusStatus = () => {
    const viewport = window.visualViewport;
    if (!focusStatus || !viewport) return;
    const style = getComputedStyle(document.documentElement);
    const inset = (edge: string) =>
      Number.parseFloat(style.getPropertyValue(`--preview-safe-${edge}`)) || 0;
    Object.assign(
      focusStatus.style,
      focusStatusPlacement(viewport, {
        left: inset("left"),
        right: inset("right"),
        bottom: inset("bottom"),
      }),
    );
    selectionActions?.position();
  };
  const korean = navigator.language.startsWith("ko");
  const showFocusStatus = (ko: string, en: string) => {
    if (!focusStatus) {
      focusStatus = document.createElement("div");
      focusStatus.className = "typst-focus-status";
      focusStatus.setAttribute("role", "status");
      focusStatus.setAttribute("aria-live", "polite");
      document.body.appendChild(focusStatus);
    }
    focusStatus.textContent = korean ? ko : en;
    positionFocusStatus();
  };

  function createSvgDocument(kModule: RenderSession) {
    const hookedElem = document.getElementById("typst-app")! as TypstDomHookedElement;
    if (hookedElem.firstElementChild?.tagName !== "svg") {
      hookedElem.innerHTML = "";
    }
    const resizeTarget = document.getElementById("typst-container-main")!;

    const svgDoc = new TypstDocument({
      windowElem,
      hookedElem,
      kModule,
      previewMode,
      isContentPreview,
      // set rescale target to `body`
      retrieveDOMState() {
        return {
          width: resizeTarget.clientWidth,
          height: resizeTarget.offsetHeight,
          boundingRect: resizeTarget.getBoundingClientRect(),
        };
      },
    });
    if (readingState) {
      svgDoc.impl.currentScaleRatio = readingState.scale;
      svgDoc.impl.partialRenderPage = readingState.page;
    }

    if (previewMode === PreviewMode.Doc && !isContentPreview) {
      const changedLocations = new ChangeLocationQueue(Boolean(readingState));
      let lastUserGesture = -Infinity;
      const navigationActions = document.createElement("div");
      navigationActions.className = "typst-navigation-actions";
      document.body.appendChild(navigationActions);
      const changeButton = document.createElement("button");
      changeButton.type = "button";
      changeButton.className = "typst-change-jump";
      changeButton.textContent = navigator.language.startsWith("ko")
        ? "변경 위치로"
        : "Jump to change";
      changeButton.hidden = true;
      navigationActions.appendChild(changeButton);

      const jumpToChange = ([page, , y]: [number, number, number]) => {
        const rect = hookedElem.querySelector<SVGRectElement>(
          `.typst-page-inner[data-page-number="${page - 1}"]`,
        );
        if (!rect) return;
        const pageHeight = Number.parseFloat(rect.getAttribute("data-page-height") || "0");
        const renderedRect = rect.getBoundingClientRect();
        const pageTop =
          renderedRect.top - resizeTarget.getBoundingClientRect().top + resizeTarget.scrollTop;
        const innerY =
          pageHeight > 0
            ? (Math.min(Math.max(y, 0), pageHeight) * renderedRect.height) / pageHeight
            : 0;
        // An instant jump avoids animating through hundreds of virtual pages.
        resizeTarget.scrollTo({
          top: Math.max(0, pageTop + innerY - resizeTarget.clientHeight * 0.35),
          behavior: "instant",
        });
        svgDoc.addViewportChange();
      };

      const showChangeButton = () => {
        changeButton.hidden = false;
      };
      changeButton.addEventListener("click", () => {
        if (changedLocations.lastLocation) jumpToChange(changedLocations.lastLocation);
        changeButton.hidden = true;
      });

      const markUserGesture = () => {
        lastUserGesture = performance.now();
      };
      const referenceNavigation = new ReferenceNavigation(
        resizeTarget,
        hookedElem,
        navigationActions,
        markUserGesture,
        () => {
          markUserGesture();
          svgDoc.addViewportChange();
        },
      );
      resizeTarget.addEventListener("pointerdown", markUserGesture, { passive: true });
      resizeTarget.addEventListener("touchmove", markUserGesture, { passive: true });
      resizeTarget.addEventListener("wheel", markUserGesture, { passive: true });
      document.addEventListener("keydown", markUserGesture);

      queueChangedLocation = (location, resume) => {
        changedLocations.queue(location, resume);
      };
      clearChangedLocation = () => {
        changedLocations.clear();
        changeButton.hidden = true;
      };
      svgDoc.impl.onDidRender = () => {
        referenceNavigation.afterRender();
        const change = changedLocations.afterRender(performance.now(), lastUserGesture);
        if (!change) return;
        if (change.deferred) {
          showChangeButton();
        } else {
          jumpToChange(change.location);
          changeButton.hidden = true;
        }
      };
      svgDoc.impl.disposeList.push(() => {
        referenceNavigation.dispose();
        navigationActions.remove();
        resizeTarget.removeEventListener("pointerdown", markUserGesture);
        resizeTarget.removeEventListener("touchmove", markUserGesture);
        resizeTarget.removeEventListener("wheel", markUserGesture);
        document.removeEventListener("keydown", markUserGesture);
        queueChangedLocation = undefined;
        clearChangedLocation = undefined;
      });
    }

    flushEditorScroll = () => {
      if (
        !pendingEditorScroll ||
        !focusRevision ||
        svgDoc.impl.isRendering ||
        svgDoc.impl.patchQueue.length ||
        !windowElem.typstWebsocket
      )
        return;
      const request = pendingEditorScroll;
      pendingEditorScroll = undefined;
      windowElem.typstWebsocket.send(
        `editor ${JSON.stringify({ ...request, revision: focusRevision })}`,
      );
    };
    const previousOnDidRender = svgDoc.impl.onDidRender;
    if (previewMode === PreviewMode.Doc && !isContentPreview) {
      selectionActions = new SelectionActions(
        hookedElem,
        (action, selection) => {
          if (
            !focusEnabled ||
            !focusRevision ||
            selection.revision !== focusRevision ||
            !windowElem.typstWebsocket
          ) {
            showFocusStatus(
              "문서 갱신 중 · 다시 선택해 주세요",
              "Document updating · select text again",
            );
            return false;
          }
          const payload = {
            ...selection.start,
            revision: selection.revision,
            selection: { text: selection.text, end: selection.end },
          };
          showFocusStatus(
            action === "save" ? "선택한 텍스트 저장 중…" : "하이라이트 적용 중…",
            action === "save" ? "Saving selected text…" : "Applying highlight…",
          );
          windowElem.typstWebsocket.send(
            `${action === "save" ? "src-point" : "src-highlight"} ${JSON.stringify(payload)}`,
          );
          return true;
        },
        () => focusRevision,
      );
    }
    let restoreReadingState = readingState;
    svgDoc.impl.onDidRender = () => {
      // Viewport callbacks before the first document (or during reconnect) do
      // not consume initial restoration or hints waiting for that document.
      if (!svgDoc.impl.moduleInitialized || awaitingFullFrame) return;
      updateActivity(() => activity.state.didRender());
      // A viewport render must not adopt a hint before its document frame arrives.
      focusRevision =
        queuedFocusRevision === pendingFocusRevision ? queuedFocusRevision : undefined;
      if (queuedFocusDocument) selectionActions?.setDocument(queuedFocusDocument);
      selectionActions?.setEnabled(focusEnabled && !!focusRevision);
      selectionActions?.afterRender();
      previousOnDidRender?.();
      flushEditorScroll();
      if (restoreReadingState) {
        const state = restoreReadingState;
        restoreReadingState = undefined;
        resizeTarget.scrollTo({ top: state.top, left: state.left, behavior: "instant" });
        svgDoc.addViewportChange();
      }
      // Capture eligibility follows both rendering and initial navigation.
      onDidRender?.(svgDoc.impl);
    };
    svgDoc.impl.onRenderActivity = (phase) =>
      updateActivity(() => activity.state.renderActivity(phase));
    svgDoc.impl.onRenderError = () => {
      updateActivity(() => activity.state.renderError());
    };
    svgDoc.impl.disposeList.push(() => {
      windowElem.onPreviewFocus = undefined;
      selectionActions?.dispose();
      selectionActions = undefined;
      focusStatus?.remove();
      focusStatus = undefined;
    });

    // Dynamic viewport units can settle after the window resize event on iOS.
    // Observe the actual scrollport; the renderer retains its existing resize anchor
    // and scale ratio. Do not resize the document to the pinch-zoomed visual viewport.
    if (typeof ResizeObserver !== "undefined") {
      const observer = new ResizeObserver(() => {
        positionFocusStatus();
        svgDoc.addViewportChange();
      });
      observer.observe(resizeTarget);
      svgDoc.impl.disposeList.push(() => observer.disconnect());
    }
    subsribes.push(fromEvent(window, "resize").subscribe(() => svgDoc.addViewportChange()));
    if (window.visualViewport) {
      for (const event of ["resize", "scroll"]) {
        subsribes.push(
          fromEvent(window.visualViewport, event)
            .pipe(auditTime(80))
            .subscribe(() => {
              positionFocusStatus();
              svgDoc.addViewportChange();
            }),
        );
      }
    }

    if (!isContentPreview) {
      subsribes.push(
        fromEvent(resizeTarget, "scroll", { passive: true })
          .pipe(auditTime(80))
          .subscribe(() => svgDoc.addViewportChange()),
      );
    }

    // Handle messages sent from the extension to the webview
    subsribes.push(
      fromEvent<MessageEvent>(window, "message").subscribe((event) => {
        const message = event.data; // The json data that the extension sent
        switch (message.type) {
          case "outline": {
            svgDoc.setOutineData(message.outline);
            break;
          }
        }
      }),
    );

    const focusInput = () => {
      const inpPageSelector = document.getElementById("typst-page-selector") as
        | HTMLSelectElement
        | undefined;
      if (inpPageSelector) {
        inpPageSelector.focus();
      }
    };

    const blurInput = () => {
      const inpPageSelector = document.getElementById("typst-page-selector") as
        | HTMLSelectElement
        | undefined;
      if (inpPageSelector) {
        inpPageSelector.blur();
      }
    };

    const updateDiff = (diff: number) => () => {
      const pageSelector = document.getElementById("typst-page-selector") as
        | HTMLSelectElement
        | undefined;

      if (pageSelector) {
        console.log("updateDiff", diff);
        const v = pageSelector.value;
        if (v.length === 0) {
          return;
        }
        const page = Number.parseInt(v) + diff;
        if (page <= 0) {
          return;
        }
        if (svgDoc.setPartialPageNumber(page)) {
          pageSelector.value = page.toString();
          blurInput();
        }
      }
    };

    const updatePrev = updateDiff(-1);
    const updateNext = updateDiff(1);

    const pagePrevSelector = document.getElementById("typst-page-prev-selector");
    if (pagePrevSelector) {
      pagePrevSelector.addEventListener("click", updatePrev);
    }
    const pageNextSelector = document.getElementById("typst-page-next-selector");
    if (pageNextSelector) {
      pageNextSelector.addEventListener("click", updateNext);
    }
    svgDoc.impl.disposeList.push(() => {
      pagePrevSelector?.removeEventListener("click", updatePrev);
      pageNextSelector?.removeEventListener("click", updateNext);
    });

    if (previewMode === PreviewMode.Slide) {
      {
        const inpPageSelector = document.getElementById("typst-page-selector") as
          | HTMLSelectElement
          | undefined;
        if (inpPageSelector) {
          const changePage = () => {
            if (inpPageSelector.value.length === 0) {
              return;
            }
            const page = Number.parseInt(inpPageSelector.value);
            svgDoc.setPartialPageNumber(page);
          };
          inpPageSelector.addEventListener("input", changePage);
          svgDoc.impl.disposeList.push(() =>
            inpPageSelector.removeEventListener("input", changePage),
          );
        }
      }
    }

    const toggleHelp = () => {
      const help = document.getElementById("typst-help-panel");
      console.log("toggleHelp", help);
      if (help) {
        help.classList.toggle("hidden");
      }
    };

    const removeHelp = () => {
      const help = document.getElementById("typst-help-panel");
      if (help) {
        help.classList.add("hidden");
      }
    };

    const toggleTheme = () => {
      if (nativeTheme) {
        onToggleTheme?.();
        return;
      }
      const typstApp = document.getElementById("typst-app");
      console.log("toggleTheme", typstApp);
      if (typstApp) {
        typstApp.classList.toggle("invert-colors");
      }
    };

    const helpButton = document.getElementById("typst-top-help-button");
    helpButton?.addEventListener("click", toggleHelp);

    const handleKeyDown = (e: KeyboardEvent) => {
      if (
        e.target instanceof HTMLElement &&
        e.target.matches("input, select, textarea, [contenteditable]")
      )
        return;
      let handled = true;

      const scrollDelta = 50;

      switch (e.key) {
        case "ArrowLeft":
        case "ArrowUp":
          if (previewMode === PreviewMode.Slide) {
            blurInput();
            removeHelp();
            updatePrev();
          }
          break;
        case " ":
        case "ArrowRight":
        case "ArrowDown":
          if (previewMode === PreviewMode.Slide) {
            blurInput();
            removeHelp();
            updateNext();
          }
          break;
        case "j":
          resizeTarget.scrollBy({ top: +scrollDelta, behavior: "instant" });
          break;
        case "k":
          resizeTarget.scrollBy({ top: -scrollDelta, behavior: "instant" });
          break;
        case "h":
          resizeTarget.scrollBy({ top: -scrollDelta * 10, behavior: "smooth" });
          break;
        case "l":
          resizeTarget.scrollBy({ top: +scrollDelta * 10, behavior: "smooth" });
          break;
        case "?":
          blurInput();
          toggleHelp();
          break;
        case "g":
          removeHelp();
          focusInput();
          break;
        case "Escape":
          removeHelp();
          blurInput();
          handled = false;
          break;
        case "t":
          toggleTheme();
          break;
        default:
          handled = false;
      }

      if (handled) {
        e.preventDefault();
      }
    };
    window.addEventListener("keydown", handleKeyDown);
    svgDoc.impl.disposeList.push(() => {
      window.removeEventListener("keydown", handleKeyDown);
      helpButton?.removeEventListener("click", toggleHelp);
    });

    return svgDoc;
  }

  function setupSocket(svgDoc: TypstDocument): () => void {
    if (!windowElem.documents.includes(svgDoc)) windowElem.documents.push(svgDoc);

    const batchMessageChannel = new Subject<{ data: ArrayBuffer; socket: object }>();
    connection = new PreviewConnection(url, {
      opened: (sock) => {
        if (disposed) return;
        awaitingFullFrame = true;
        updateActivity(() => activity.state.opened());
        console.log("WebSocket connection opened", sock);
        windowElem.typstWebsocket = sock as any;
        clearChangedLocation?.();
        focusRevision = pendingFocusRevision = undefined;
        pendingFocusDocument = undefined;
        queuedFocusRevision = queuedFocusDocument = undefined;
        focusEnabled = false;
        selectionActions?.setEnabled(false);
        windowElem.onPreviewFocus = undefined;
        windowElem.typstWebsocket.send("current");
      },
      message: (data, socket) => batchMessageChannel.next({ data, socket }),
      disconnected: () => {
        if (disposed) return;
        updateActivity(() => activity.state.disconnected());
        windowElem.typstWebsocket = undefined as any;
        focusRevision = pendingFocusRevision = undefined;
        focusEnabled = false;
        selectionActions?.setEnabled(false);
        if (focusStatus)
          showFocusStatus(
            "연결 끊김 · 다시 연결한 뒤 탭해 주세요",
            "Disconnected · reconnect, then tap again",
          );
      },
    });

    const dispose = () => {
      disposed = true;
      activity.dispose();
      connection?.dispose();
      editorNavigation.dispose();
      pendingEditorScroll = undefined;
      flushEditorScroll = () => {};
      svgDoc.dispose();
      const index = windowElem.documents.indexOf(svgDoc);
      if (index >= 0) {
        windowElem.documents.splice(index, 1);
      }
      for (const sub of subsribes.splice(0, subsribes.length)) {
        sub.unsubscribe();
      }
      batchMessageChannel.complete();
      windowElem.typstWebsocket = undefined as any;
    };

    subsribes.push(
      batchMessageChannel
        .pipe(buffer(batchMessageChannel.pipe(debounceTime(0))))
        .pipe(
          tap((dataList) => {
            console.log(`batch ${dataList.length} messages`);
          }),
        )
        .subscribe((dataList) => {
          dataList.forEach(({ data, socket }) => {
            if (windowElem.typstWebsocket === socket) processMessage(data);
          });
        }),
    );

    function processMessage(data: ArrayBuffer) {
      if (disposed) return;
      if (!(data instanceof ArrayBuffer)) {
        if (data === NOT_AVAILABLE) {
          return;
        }

        console.error("WebSocket data is not a ArrayBuffer", data);
        return;
      }

      const message = decodePreviewFrame(data);
      if (!message) {
        console.error("Malformed preview frame");
        return;
      }
      console.log("recv", message[0], data.byteLength);
      if (message[0] === "keepalive") {
        if (dec.decode(message[1] as Uint8Array) === "true") connection?.supportPing();
        return;
      }
      if (message[0] === "pong") return;
      if (message[0] === "compile-status") {
        updateActivity(() => activity.state.compile(dec.decode(message[1] as Uint8Array)));
        return;
      }
      if (message[0] === "focus-enabled") {
        focusEnabled = true;
        selectionActions?.setEnabled(!!focusRevision);
        showFocusStatus(
          editorNavigation.enabled
            ? "본문을 클릭하면 VS Code 소스로 이동합니다"
            : "Codex에 위치 공유 · 본문을 탭하세요",
          editorNavigation.enabled
            ? "Click the document to reveal its source in VS Code"
            : "Share a location with Codex · tap the document",
        );
        windowElem.onPreviewFocus = (position) => {
          if (hasTouchSelection(svgDoc.impl.hookedElem)) return;
          if (!focusRevision || svgDoc.impl.isRendering || svgDoc.impl.patchQueue.length) {
            showFocusStatus(
              "문서 갱신 중 · 잠시 후 다시 탭해 주세요",
              "Document updating · tap again shortly",
            );
            return;
          }
          showFocusStatus(
            editorNavigation.enabled ? "소스 위치 찾는 중…" : "선택한 위치 저장 중…",
            editorNavigation.enabled ? "Finding source location…" : "Saving selected location…",
          );
          windowElem.typstWebsocket.send(
            `${editorNavigation.enabled ? "src-editor" : "src-point"} ${JSON.stringify({ ...position, revision: focusRevision })}`,
          );
        };
        return;
      }
      if (message[0] === "focus-revision") {
        pendingFocusRevision = dec.decode(message[1] as Uint8Array);
        focusRevision = undefined;
        selectionActions?.setEnabled(false);
        return;
      }
      if (message[0] === "focus-document") {
        const id = dec.decode(message[1] as Uint8Array);
        if (/^[a-f0-9]{32}$/.test(id)) pendingFocusDocument = id;
        return;
      }
      if (message[0] === "highlight") {
        const result = JSON.parse(dec.decode(message[1] as Uint8Array));
        selectionActions?.highlightFinished(result.status);
        if (result.status === "highlighted") {
          showFocusStatus(
            "소스에 하이라이트 저장됨 · 컴파일 중",
            "Highlight saved in source · compiling",
          );
        } else if (result.status === "stale") {
          showFocusStatus(
            "문서가 갱신됐습니다 · 다시 선택해 주세요",
            "Document changed · select text again",
          );
        } else if (result.status === "unmapped" || result.status === "unsupported") {
          showFocusStatus(
            "소스 범위를 정확히 연결할 수 없습니다 · Codex 저장을 사용하세요",
            "Cannot safely map this source range · use Save for Codex",
          );
        } else {
          showFocusStatus(
            "하이라이트 저장 실패 · 다시 선택해 주세요",
            "Could not save highlight · select text again",
          );
        }
        return;
      }
      if (message[0] === "editor") {
        const result = JSON.parse(dec.decode(message[1] as Uint8Array));
        if (
          result.event === "editorScrollTo" &&
          result.revision === focusRevision &&
          !svgDoc.impl.isRendering &&
          !svgDoc.impl.patchQueue.length
        ) {
          const sent = editorNavigation.reveal(result);
          showFocusStatus(
            sent ? "VS Code에 소스 위치 전달됨" : "VS Code에서 미리보기를 다시 열어 주세요",
            sent ? "Source location sent to VS Code" : "Reopen this preview from VS Code",
          );
        } else if (result.status === "stale" || result.event === "editorScrollTo") {
          showFocusStatus(
            "문서가 갱신됐습니다 · 다시 클릭해 주세요",
            "Document changed · click again",
          );
        } else {
          showFocusStatus("소스 위치를 연결할 수 없습니다", "Source location unavailable");
        }
        return;
      }
      if (message[0] === "focus") {
        const result = JSON.parse(dec.decode(message[1] as Uint8Array));
        if (result.status === "selected") {
          const name = result.filepath.split(/[\\/]/).pop();
          showFocusStatus(
            `Codex용 ${result.text_selected ? "텍스트" : "위치"} 저장됨 · ${result.page}쪽 · ${name}:${result.line}`,
            `Saved ${result.text_selected ? "text " : ""}for Codex · p. ${result.page} · ${name}:${result.line}`,
          );
        } else if (result.status === "unmapped") {
          showFocusStatus(
            result.text_selected
              ? `Codex용 텍스트 저장됨 · ${result.page}쪽 · 소스 연결 없음`
              : `${result.page}쪽 위치만 저장됨 · 글자를 탭하면 소스도 연결됩니다`,
            result.text_selected
              ? `Text saved for Codex · p. ${result.page} · source unavailable`
              : `Page ${result.page} location saved · tap text to link its source`,
          );
        } else if (result.status === "stale" || result.status === "not_ready") {
          showFocusStatus("문서가 갱신됐습니다 · 다시 탭해 주세요", "Document changed · tap again");
        } else {
          showFocusStatus(
            "위치 저장 실패 · 다시 탭해 주세요",
            "Could not save location · tap again",
          );
        }
        return;
      }
      // console.log(message[0], message[1].length);
      if (isContentPreview) {
        // whether to scroll to the content preview when user updates document
        const autoScrollContentPreview = true;
        if (!autoScrollContentPreview && message[0] === "jump") {
          return;
        }

        // "viewport": viewport change to document doesn't affect content preview
        // "partial-rendering": content previe always render partially
        // "cursor": currently not supported
        if (
          message[0] === "viewport" ||
          message[0] === "partial-rendering" ||
          message[0] === "cursor"
        ) {
          return;
        }
      }

      if (message[0] === "change" || message[0] === "resume") {
        const location = parseChangeLocation(dec.decode(message[1] as Uint8Array));
        if (location) queueChangedLocation?.(location, message[0] === "resume");
        return;
      }

      if (message[0] === "jump" || message[0] === "viewport") {
        const rootElem = document.getElementById("typst-app")?.firstElementChild;

        // todo: aware height padding
        let currentPageNumber = 1;
        if (previewMode === PreviewMode.Slide) {
          currentPageNumber = svgDoc.getPartialPageNumber();
        } else if (rootElem) {
          currentPageNumber = windowElem.currentPosition(rootElem)?.page || 1;
        }

        let positions = dec
          .decode(message[1])
          .split(",")
          .map((t: string) => t.trim())
          .filter((t: string) => t.length > 0);

        // choose the page, x, y closest to the current page
        const [page, x, y] = positions.reduce(
          (acc, cur) => {
            const [page, x, y] = cur.split(" ").map(Number);
            const current_page = currentPageNumber;
            // If page distance is the same, choose the last one
            if (Math.abs(page - current_page) <= Math.abs(acc[0] - current_page)) {
              return [page, x, y];
            }
            return acc;
          },
          [Number.MAX_SAFE_INTEGER, 0, 0],
        );
        // console.log("resolved", page, x, y, "from", currentPageNumber);

        let pageToJump = page;
        if (pageToJump === Number.MAX_SAFE_INTEGER) {
          return;
        }

        if (previewMode === PreviewMode.Slide) {
          const pageSelector = document.getElementById("typst-page-selector") as
            | HTMLSelectElement
            | undefined;
          if (svgDoc.setPartialPageNumber(page)) {
            if (pageSelector) {
              pageSelector.value = page.toString();
            }
            // pageToJump = 1;
            // todo: hint location
            return;
          } else {
            return;
          }
        }

        if (rootElem) {
          /// Note: when it is really scrolled, it will trigger `svgDoc.addViewportChange`
          /// via `window.onscroll` event
          windowElem.handleTypstLocation(rootElem, pageToJump, x, y);
        }
        return;
      } else if (message[0] === "cursor") {
        // todo: aware height padding
        const [page, x, y] = dec.decode(message[1]).split(" ").map(Number);
        console.log("cursor", page, x, y);
        svgDoc.setCursor(page, x, y);
        svgDoc.addViewportChange(); // todo: synthesizing cursor event
        return;
      } else if (message[0] === "cursor-paths") {
        // todo: aware height padding
        const paths = JSON.parse(dec.decode(message[1]));
        console.log("cursor-paths", paths);
        svgDoc.impl.setCursorPaths(paths);
        return;
      } else if (message[0] === "partial-rendering") {
        console.log("Experimental feature: partial rendering enabled");
        svgDoc.setPartialRendering(true);
        return;
      } else if (message[0] === "invert-colors") {
        if (nativeTheme) {
          document.getElementById("typst-app")?.classList.remove("invert-colors", "normal-image");
          return;
        }
        const rawStrategy = dec.decode(message[1]).trim();
        const strategy =
          INVERT_COLORS_STRATEGY.find((t) => t === rawStrategy) ||
          (JSON.parse(rawStrategy) as StrategyMap);
        console.log("Experimental feature: invert colors strategy taken:", strategy);
        ensureInvertColors(document.getElementById("typst-app"), strategy);
        return;
      } else if (message[0] === "outline") {
        console.log("Experimental feature: outline rendering");
        return;
      }

      if (handleHtmlPreviewFrame(message[0] as string, message[1] as Uint8Array, url, dec)) {
        return;
      }

      if (message[0] === "new" || message[0] === "diff-v1") {
        // A fresh server renderer can emit an unsolicited delta before replying
        // to `current`. It has no common baseline with the retained client model.
        if (awaitingFullFrame && message[0] === "diff-v1") {
          clearChangedLocation?.();
          return;
        }
        awaitingFullFrame = false;
        updateActivity(() => activity.state.frame());
        queuedFocusRevision = pendingFocusRevision;
        queuedFocusDocument = pendingFocusDocument;
      }
      svgDoc.addChangement(message as any);
    }

    return dispose;
  }

  try {
    const plugin = createTypstRenderer();
    await plugin.init({ getModule: () => renderModule });
    console.log("plugin initialized, build info:", await rendererBuildInfo());
    updateActivity(() => activity.state.connecting());
    return await new Promise<() => void>((resolveDispose, reject) => {
      plugin
        .runWithSession(
          (kModule) =>
            new Promise((kernelDispose) => {
              try {
                const wsDispose = setupSocket(createSvgDocument(kModule));
                resolveDispose(() => {
                  wsDispose();
                  kernelDispose(undefined);
                });
              } catch (error) {
                kernelDispose(undefined);
                reject(error);
              }
            }),
        )
        .catch(reject);
    });
  } catch (error) {
    console.error("Preview renderer failed", error);
    updateActivity(() => activity.state.renderError());
    return () => activity.dispose();
  }
}

/** The strategy to set invert colors, see editors/vscode/package.json for enum descriptions */
const INVERT_COLORS_STRATEGY = ["never", "auto", "always"] as const;
/** The value of strategy constant */
type StrategyKey = (typeof INVERT_COLORS_STRATEGY)[number];
/** The map from element kinds to strategy */
type StrategyMap = Partial<Record<"rest" | "image", StrategyKey>>;

function ensureInvertColors(root: HTMLElement | null, strategy: StrategyKey | StrategyMap) {
  if (!root) {
    return;
  }

  // Uniforms type of strategy to `TargetMap`
  if (typeof strategy === "string") {
    strategy = { rest: strategy };
  }

  let autoDecision: { value: boolean } | undefined = undefined;
  /**
   * Handles invert colors mode based on a string enumerated strategy.
   * @param strategy - The strategy set by user.
   * @returns needInvertColor - Use or not use invert color.
   */
  const decide = (strategy: StrategyKey) => {
    switch (strategy) {
      case "never":
        return false;
      default:
        console.warn("Unknown invert-colors strategy:", strategy);
        return false;
      case "auto":
        return (autoDecision ||= { value: determineInvertColor() }).value;
      case "always":
        return true;
    }
  };

  root.classList.toggle("invert-colors", decide(strategy?.rest || "never"));
  root.classList.toggle("normal-image", !decide(strategy?.image || strategy?.rest || "never"));

  function determineInvertColor() {
    const vscodeAPI = typeof acquireVsCodeApi !== "undefined";

    if (vscodeAPI) {
      // vscode-dark, high-contrast, vscode-light
      const cls = document.body.classList;
      const themeIsDark =
        (cls.contains("vscode-dark") || cls.contains("vscode-high-contrast")) &&
        !cls.contains("vscode-light");

      if (themeIsDark) {
        console.log("invert-colors because detected by vscode theme", document.body.className);
        return true;
      }
    } else {
      // prefer dark mode
      if (window.matchMedia("(prefers-color-scheme: dark)").matches) {
        console.log("invert-colors because detected by (prefers-color-scheme: dark)");
        return true;
      }
    }

    console.log("doesn't invert-colors because none of dark mode detected");
    return false;
  }
}

import { ChangeLocationQueue, type ChangeLocation } from "./change-location";
import { ReferenceNavigation } from "./reference-navigation";

/** Page geometry adapter for shared render-before-jump and reading-gesture policy. */
export function createChangeNavigation({
  hookedElem,
  resizeTarget,
  preserveReadingState,
  viewportChanged,
}: {
  hookedElem: HTMLElement;
  resizeTarget: HTMLElement;
  preserveReadingState: boolean;
  viewportChanged: () => void;
}) {
  const changedLocations = new ChangeLocationQueue<ChangeLocation>(preserveReadingState);
  let lastUserGesture = -Infinity;
  const navigationActions = document.createElement("div");
  navigationActions.className = "typst-navigation-actions";
  document.body.appendChild(navigationActions);
  const changeButton = document.createElement("button");
  changeButton.type = "button";
  changeButton.className = "typst-change-jump";
  changeButton.textContent = navigator.language.startsWith("ko") ? "변경 위치로" : "Jump to change";
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
    viewportChanged();
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
      viewportChanged();
    },
  );
  resizeTarget.addEventListener("pointerdown", markUserGesture, { passive: true });
  resizeTarget.addEventListener("touchmove", markUserGesture, { passive: true });
  resizeTarget.addEventListener("wheel", markUserGesture, { passive: true });
  document.addEventListener("keydown", markUserGesture);

  const queue = (location: ChangeLocation, resume: boolean) => {
    changedLocations.queue(location, resume);
  };
  const clear = () => {
    changedLocations.clear();
    changeButton.hidden = true;
  };
  const afterRender = () => {
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
  const dispose = () => {
    referenceNavigation.dispose();
    navigationActions.remove();
    resizeTarget.removeEventListener("pointerdown", markUserGesture);
    resizeTarget.removeEventListener("touchmove", markUserGesture);
    resizeTarget.removeEventListener("wheel", markUserGesture);
    document.removeEventListener("keydown", markUserGesture);
  };
  return { queue, clear, afterRender, dispose };
}

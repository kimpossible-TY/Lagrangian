const terminationReasons = {
  "page-hidden":
    "화면이 백그라운드로 전환되어 계산을 중단했습니다. 앱 전환·화면 잠금은 구분할 수 없습니다.",
  "page-exit": "페이지를 떠나거나 다시 불러와 계산을 중단했습니다.",
  offline: "브라우저가 오프라인 상태를 감지했습니다.",
  disabled: "이 기기 계산 돕기를 꺼서 중단했습니다.",
  disposed: "Reader가 계산 연결을 정리했습니다.",
  "transport-error":
    "서버 통신 요청에 실패했습니다. 네트워크 단절과 서버 응답 오류는 추가 확인이 필요합니다.",
  "worker-error": "계산 Worker에서 오류가 발생했습니다. 메모리 부족 여부는 확인되지 않았습니다.",
  "compile-error": "기기 컴파일러가 계산 오류를 보고했습니다.",
  "client-timeout": "기기 계산의 제한 시간이 지났습니다.",
  "heartbeat-lost":
    "기기의 주기적 응답이 끊겼습니다. 브라우저 종료·네트워크·메모리 부족 중 원인은 확인되지 않았습니다.",
  released: "기기가 연결을 종료했습니다. 상세 원인은 보고되지 않았습니다.",
};
const phases = {
  ready: "준비 완료",
  received: "입력 수신",
  fonts: "글꼴 준비",
  files: "입력 파일 준비",
  evaluating: "Typst 계산",
  output: "출력 추출",
  "sending-result": "결과 전송",
};
function executionEvidence(event) {
  const end = event.termination;
  const progress = end?.lastProgress || event.recovery?.progress;
  const details = [];
  if (progress) {
    details.push(`마지막 단계: ${phases[progress.phase] || progress.phase}.`);
    if (progress.wasmMemoryBytes !== undefined)
      details.push(
        `당시 WASM 할당 ${(progress.wasmMemoryBytes / 1048576).toFixed(1)}MiB (최대값·기기 전체 메모리가 아님).`,
      );
  }
  if (end?.lastHeartbeatAgeSeconds !== undefined)
    details.push(`마지막 응답 이후 ${end.lastHeartbeatAgeSeconds}초.`);
  if (event.recovery)
    details.push(
      event.recovery.mode === "page-restart"
        ? "페이지가 다시 시작되어 재연결됐습니다. 자동·수동 새로고침 여부는 이 기록만으로 구분하지 못합니다."
        : "같은 페이지에서 계산 연결만 다시 만들었습니다.",
    );
  return details.join(" ");
}
function terminationText(event) {
  const end = event.termination;
  if (!end) return "";
  return (
    terminationReasons[end.reason] ||
    (end.status === "timeout"
      ? "검사 제한 시간이 지났습니다."
      : end.status === "invalid-result"
        ? "서버가 기기 계산 결과를 거절했습니다."
        : "계산 연결이 종료됐으나 상세 원인은 확인되지 않았습니다.")
  );
}
const reasons = {
  "client-update-required":
    "기기에 이전 버전이 남아 있습니다. 읽기 설정에서 ‘업데이트 적용’을 누르세요. 버튼이 없으면 Reader 탭과 홈 화면 앱을 모두 닫고 다시 열어 주세요.",
  "snapshot-unavailable": "기기에 보낼 문서 입력을 준비하지 못했습니다. 결과를 복사해 알려 주세요.",
  "device-not-ready": "이 기기가 준비되지 않았거나 다른 계산 중입니다. 잠시 후 다시 눌러 주세요.",
  "test-already-running": "다른 검사가 진행 중입니다. 완료 후 다시 눌러 주세요.",
  "document-not-ready": "문서 컴파일이 끝난 뒤 다시 검사해 주세요.",
  "source-changed": "검사 중 문서가 바뀌었습니다. 편집을 멈춘 뒤 다시 검사해 주세요.",
  "device-did-not-finish": "기기 계산 결과를 받지 못했습니다. 종료 기록을 복사해 알려 주세요.",
  "reference-failed": "서버 기준 결과를 만들지 못했습니다. 결과를 복사해 알려 주세요.",
  "output-mismatch": "기기와 서버의 결과가 달랐습니다. 결과를 복사해 알려 주세요.",
  "content-rejected": "문서 내용 검증을 통과하지 못했습니다. 결과를 복사해 알려 주세요.",
  "check-failed": "검사를 완료하지 못했습니다. 결과를 복사해 알려 주세요.",
};
const purposes = {
  connection: "계산 연결",
  "dynamic-warm": "그림 계산 준비",
  quick: "간단 검사",
  document: "문서",
  "test-quick": "간단 검사 계산",
  "test-document": "문서 검사 계산",
  "source-map": "소스 위치 확인",
  graphics: "그림",
  canvases: "도형",
  decorations: "수식 장식",
  compile: "검증 계산",
};
const statuses = {
  queued: "대기",
  working: "계산 중",
  "result-received": "계산 결과 수신",
  timeout: "시간 초과",
  disconnected: "연결 종료",
  reconnected: "재연결",
  "invalid-result": "결과 거절",
  failed: "실패",
  passed: "검사 통과",
  running: "검사 중",
  published: "문서 반영 완료",
};
const fallbackReasons = {
  "no-ready-device": "준비된 기기가 없거나 작업 중",
  "browser-unfinished": "기기 계산 미완료",
  "snapshot-unavailable": "기기에 보낼 입력 준비 불가",
};

export function compilerDiagnostics(client, preferences) {
  const panel = document.querySelector("#reader-compiler-diagnostics");
  const result = document.querySelector("#reader-diagnostic-result");
  const buttons = [...panel.querySelectorAll("[data-diagnostic]")];
  let testID = preferences.read("compiler-test-id");
  let timer,
    disposed = false,
    report = "",
    running = false,
    starting = false,
    startError = "";

  const render = (status) => {
    if (starting) return;
    const device = client.device;
    document.querySelector("#reader-device-identity").textContent = device
      ? `이 기기: ${device.name} · ${device.id} · 진단 ${device.diagnosticsVersion || 0}`
      : "계산 돕기를 켜고 이 화면에서 기기 준비가 끝날 때까지 기다려 주세요.";
    const event = status.history.find((item) => item.id === testID);
    running = event?.status === "running";
    for (const button of buttons)
      button.disabled = !device || running || !device.diagnosticsVersion;
    if (event) {
      const name = event.purpose === "quick" ? "간단 검사" : "현재 문서 검사";
      const who = `${event.device.name} · ${event.device.id}`;
      const baseText =
        event.status === "passed"
          ? `통과 — ${name}: ${who}가 직접 계산했고 서버 기준 결과와 일치합니다. 기기 응답 ${event.deviceSeconds}초.`
          : event.status === "failed"
            ? `미통과 — ${name}: ${terminationText(event) || reasons[event.reason] || reasons["check-failed"]}`
            : event.stage === "reference"
              ? "기기 계산 완료. 서버 기준 결과와 비교하고 있습니다."
              : "검사 중 — 이 화면을 열어 두세요. 기기의 계산 결과를 기다리고 있습니다.";
      const text = [baseText, executionEvidence(event)].filter(Boolean).join(" ");
      if (result.textContent !== text) result.textContent = text;
      result.dataset.status = event.status;
      report = `Flow 기기 계산 검사\n${text}\n${JSON.stringify(event, null, 2)}`;
    } else if (startError) {
      result.textContent = startError;
    } else if (testID) {
      result.textContent =
        "검사 기록이 없습니다. 서버가 재시작되었거나 기록 보관 범위를 지났습니다. 다시 검사해 주세요.";
    } else {
      result.textContent =
        !device && client.lastError
          ? `기기 계산 연결을 준비하지 못했습니다: ${client.lastError}. 새로고침 후에도 반복되면 결과를 복사해 알려 주세요.`
          : device && !device.diagnosticsVersion
            ? reasons["client-update-required"]
            : device
              ? "준비됐습니다. ‘1. 간단 검사’를 눌러 주세요."
              : "기기 연결을 기다리고 있습니다.";
    }
    const list = (selector, rows) => {
      document.querySelector(selector).replaceChildren(
        ...rows.map((text) => {
          const li = document.createElement("li");
          li.textContent = text;
          return li;
        }),
      );
    };
    list(
      "#reader-compiler-devices",
      status.workers.map(
        (item) =>
          `${item.name} · ${item.id}${item.id === device?.id ? " (이 기기)" : ""}: ${item.busy ? "계산 중" : "준비됨"}, ${item.lastSeenSeconds}초 전 응답`,
      ),
    );
    list(
      "#reader-compiler-history",
      status.history.slice(0, 12).map((item) => {
        const owner = item.device
          ? `${item.device.name} · ${item.device.id}`
          : item.executor === "publication"
            ? "서버 검증"
            : "서버";
        const reason = terminationReasons[item.reason] || fallbackReasons[item.reason];
        return `${new Date(item.at * 1000).toLocaleTimeString()} · ${owner} · ${purposes[item.purpose] || item.purpose}: ${statuses[item.status] || item.status}${reason ? ` (${reason})` : ""}${item.elapsedSeconds !== undefined ? ` · ${item.elapsedSeconds}초` : ""}${item.revision ? ` · 문서 ${item.revision}` : ""}`;
      }),
    );
  };
  const refresh = async () => {
    clearTimeout(timer);
    if (disposed || !panel.open || document.visibilityState !== "visible") return;
    try {
      const response = await fetch(new URL("../api/compiler/status", import.meta.url), {
        cache: "no-store",
        signal: AbortSignal.timeout(8000),
      });
      if (!response.ok) throw new Error("status-unavailable");
      const status = await response.json();
      if (!disposed) render(status);
    } catch {
      result.textContent =
        "서버 연결을 확인해 주세요. 연결이 돌아오면 검사 결과를 다시 확인합니다.";
      for (const button of buttons) button.disabled = true;
    } finally {
      if (!disposed) timer = setTimeout(refresh, 2000);
    }
  };
  for (const button of buttons)
    button.addEventListener("click", async () => {
      starting = true;
      startError = "";
      report = "";
      testID = null;
      preferences.write("compiler-test-id", null);
      result.dataset.status = "running";
      result.textContent = "검사를 시작하고 있습니다.";
      for (const item of buttons) item.disabled = true;
      try {
        const response = await client.diagnose(button.dataset.diagnostic);
        testID = response.id;
        preferences.write("compiler-test-id", testID);
        starting = false;
        await refresh();
      } catch (error) {
        starting = false;
        result.dataset.status = "failed";
        startError =
          reasons[error.message] ||
          "검사 시작을 확인하지 못했습니다. 기기 준비 상태를 확인하고 다시 눌러 주세요.";
        result.textContent = startError;
        for (const item of buttons) item.disabled = !client.device;
      }
    });
  document.querySelector("#reader-diagnostic-copy").addEventListener("click", async () => {
    const feedback = document.querySelector("#reader-diagnostic-copy-status");
    try {
      await navigator.clipboard.writeText(report || result.textContent);
      feedback.textContent = "복사했습니다. Codex 대화에 붙여 넣어 주세요.";
    } catch {
      feedback.textContent = "복사하지 못했습니다. 위 결과 문장을 선택해 복사해 주세요.";
    }
  });
  panel.addEventListener("toggle", refresh);
  document.addEventListener("visibilitychange", refresh);
  return {
    dispose() {
      disposed = true;
      clearTimeout(timer);
      panel.removeEventListener("toggle", refresh);
      document.removeEventListener("visibilitychange", refresh);
    },
  };
}

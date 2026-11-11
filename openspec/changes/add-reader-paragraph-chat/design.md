# Design

## Context

Reader에서 긴 문서를 읽는 사용자는 특정 문단이나 수식의 도출 과정, 맥락에 대해 질문하고 그 해답을 문서와 함께 보존하기를 원한다.
현재 Reader의 Saved for Codex 기능은 선택 문맥을 저장만 하는 편도 흐름이며 어시스턴트 턴이나 대화 지속성을 제공하지 않는다.
동시에 넓은 화면 지원을 위한 활성 변경인 `add-responsive-reader`가 개발 중이며, 본 문단 대화 기능은 해당 반응형 레이아웃 위에서 동작하면서 주석 및 각주와의 시각적·공간적 충돌 없이 공존해야 한다.

## Goals / Non-Goals

### Goals

- 문단 또는 구절 단위의 명시적 선택을 통한 스트리밍 대화 지원.
- 소스 저장소 외부의 비공개 호스트 로컬 저장소에 문서별·문단별 지속 대화 기록 보존.
- 서비스 재시작 후에도 안정적인 문서 ID를 기반으로 대화를 복원하고, `service_id`는 요청 메타데이터로 분리.
- 인용문, 문맥, 문서 신원 등의 결합 증거를 바탕으로 앵커를 유일하게 재부착하고, 모호하거나 삭제된 경우 기록을 안전하게 보존.
- 접힌 한 줄 요약은 문단 인근에 배치하고, 확장 시 연관 문단 바로 아래 흐름(in flow directly below associated paragraph)에 대화를 전개.
- 가로 w/3(본문 인라인 빈 공간) + 2w/3(축소된 우측 여백) 기하 배치 및 세로 국소 여백 탐색을 통한 잉크·수식·주석 비침범 보장.
- 단일 OAuth(Sign in with ChatGPT) 인증 기반 아래 직접 Responses API 전송 또는 Codex app-server 전송 브리지를 서비스에 주입.

### Non-Goals

- 임의의 LLM provider를 수용하기 위한 범용 provider 추상화 프레임워크 구축 (YAGNI 원칙 준수).
- 과거 ChatGPT 대화나 은퇴한 quote library의 데이터 마이그레이션 또는 임포트.
- 소스 문서 원본(Typst/Markdown 등)의 변형(source mutation).
- 자동 실계정 로그인, 외부 Codex 자격 증명 재사용, 유료 라이브 추론, 서비스 설치/재시작.
- 모호하거나 삭제된 문단의 대화를 임의의 다른 문단으로 강제 자동 재배치.

## Decisions

### 1. 서비스 소유권과 주입 경계

단일 만능 서비스(catch-all service)를 두지 않고 명확한 책임 경계를 설정한다.

- 지속 대화 저장소 및 앵커 증거는 `flow_reader/services/paragraph_chat.py`가 소유한다.
- Provider 인증 및 전송 경계는 서비스에 주입(injected)되며, 범용 프레임워크를 추가하지 않고 단일 인증/전송 브리지로 구성한다.
- `server/http.py`는 오직 HTTP 요청 라우팅과 스트리밍 응답 전달만 담당한다.
- 브라우저 저장소에는 대화 기록의 권위 있는 사본을 두지 않으며, 프론트엔드 어댑터는 표시 상태(열림/닫힘, 포커스)만 관리한다.

### 2. 기하 및 레이아웃: w/3 + 2w/3과 인근 여백 탐색

본문 컬럼의 인라인 끝 콘텐츠 가장자리를 $x_e$, 말풍선 폭을 $w$라 할 때 가로 배치 구간은 다음과 같다:

$$x_{\text{left}} = x_e - \frac{w}{3}, \qquad x_{\text{right}} = x_e + \frac{2w}{3}$$

- **가로 배치**: 안쪽 $w/3$은 본문 읽기 컬럼의 인라인 빈 공간에 위치하고, 바깥 $2w/3$은 축소된 우측 페이지 여백 띠에 놓인다. 본문 글자, 수식, 수식 번호, 주석과 절대 겹치지 않아야 한다.
- **세로 배치**: 대상 문단의 첫 줄에 경직되게 고정하지 않고, 문단에 인접한 사용 가능한 국소 빈 공간을 먼저 탐색하여 배치한다.
- **인라인 폴백**: 여백이나 빈 공간이 부족한 좁은 화면 또는 충돌 발생 시, 말풍선을 억지로 압축하거나 겹치지 않고 연관 문단 흐름 안의 인라인 표시로 전환한다.
- 접힌 말풍선은 문단 인근에 배치되며, 확장 시에는 연관 문단 바로 아래 흐름(in flow directly below associated paragraph)에 펼쳐진다.

### 3. 활성 변경 `add-responsive-reader`와의 관계 및 대체 규칙

본 문단 대화 레이아웃이 활성화될 때, 활성 변경인 `add-responsive-reader`의 'Connected local side columns' 및 'Viewport and text-size changes' 시나리오에 정의된 배치 및 구분선 측면을 명시적으로 대체한다.

- **긴 주석 및 각주**: 기존 국소 사이드 컬럼 대신 사용 가능한 국소 빈 공간과 좁은 **왼쪽** 여백으로 이동한다.
- **구분선 제거**: 노트 영역을 본문 페이지와 나누던 세로 구분선을 제거하고, 페이지 전체와 좌우 여백에 동일한 `--paper` 배경을 유지한다.
- **지시선 유지**: 유의미한 연결 지시선(accent leader with target dot)은 유지하되, 대화 말풍선에는 연결선을 그리지 않는다.
- **짧은 mannot 표기**: 수식 인근의 근접 라벨 표시(개념 3)를 그대로 유지하며 대화가 이 자리를 침범하지 않는다.
- **표준 본문 보존**: 기존의 정규 본문 내용, 번호 체계, 앵커 ID, 텍스트 복사 동작, 컴팩트 팝오버는 그대로 보존된다.
- `specs/reader-paragraph-chat/spec.md`의 ADDED 요구사항이 활성 HTML/terminal 문단 대화의 주석 공존 규칙과 뷰포트/글꼴 변경 시나리오를 소유한다. `add-responsive-reader` 원본은 수정하지 않으며, paged 및 문단 대화가 비활성화된 Reader는 기존 주석 배치 계약을 유지한다.

### 4. 지속 대화 기록, 신원 및 앵커 재부착

- **비밀값 격리 및 저장소 위치**: 자격 증명, 토큰 등 비밀값은 브라우저 응답/저장소, 대화 기록, 소스 저장소, 로그에 절대 저장하지 않는다. 대화 기록 본문은 소스 저장소 외부의 비공개 호스트 로컬 저장소에 격리 보존된다.
- **서비스 인스턴스와 문서 신원**: `service_id`는 일시적인 요청 메타데이터일 뿐 지속적인 문서 신원을 대체하지 않는다. 서비스 재시작 후에도 안정적인 문서 ID를 통해 대화 기록이 올바르게 복원된다.
- **문단별 독립 기록**: 동일 문서 내 서로 다른 두 문단은 완전히 분리된 대화 기록을 가지며, 한 문단의 후속 질문이 다른 문단의 기록을 변경하거나 합쳐지지 않는다.
- **결합 증거 기반 재부착**: 앵커 재부착은 단순 인용문 횟수가 아니라 문서 신원, 인용문, 사용 가능한 경우 문맥 및 소스 오프셋을 결합한 유일 증거를 통해 판정한다.
- **모호/삭제된 앵커 보존**: 인용문, 문맥, 소스 위치, 문서 신원의 결합 증거로도 유일하게 위치를 확정하지 못하거나(모호성 발생) 문단이 삭제된 경우에만 고아(미해결) 대화로 남기며, 임의의 다른 문단으로 재배치하거나 삭제하지 않는다. 미해결 기록은 문서 다음의 접근 가능한 별도 영역에서 열람한다. 인접 문단에 임의로 재배치하지 않는다.
- **장애 시 초안 보존**: 인증 실패나 네트워크 단절 시에도 기존 기록과 작성 중인 초안은 안전하게 보존되며, 실패 상태를 사실대로 표시하고 가짜 답변을 생성하지 않는다.

### 5. Approved transport decision (2026-11-01)

Primary path: direct Sign in with ChatGPT public-client PKCE and Responses HTTP/SSE. `chat_auth.py` owns loopback authorization, protected 0600 credential registrations, stable host ID, signature/issuer/audience/nonce/time checks, serialized rotating refresh and best-effort remote revocation with honest local sign-out. Native Node crypto verifies JWKS signatures through a fixed stdin helper; Node.js is required for sign-in. No model tool can invoke that helper. Existing Codex credentials, API keys, shell environment secrets and browser cookies are never imported.

Official app-server documentation and installed CLI 0.164.0 experimental JSON schemas were inspected. Built-in `account/login/start` with `type=chatgpt` delegates token persistence/refresh to Codex, but `dynamicTools` adds tools alongside the built-in harness. Its public thread protocol does not expose the extension-only startup `ToolPolicy.allowed_tools` ceiling. Read-only sandboxing still permits reads and shell execution; an instruction to avoid them is insufficient for this product. Rather than depend on internal model catalog overrides, direct Responses exposes exactly two namespace functions. No app-server or second transport is implemented.

Official sources checked:

- https://developers.openai.com/siwc/token-sharing-open-source/sign-in
- https://developers.openai.com/siwc/token-sharing-open-source/profiles-and-sessions
- https://developers.openai.com/siwc/token-sharing-open-source/models-and-inference
- https://developers.openai.com/siwc/token-sharing-open-source/preview-limitations
- https://learn.chatgpt.com/docs/app-server
- https://github.com/openai/codex/blob/main/codex-rs/ext/extension-api/src/tool_policy.rs

Loopback is required only for starting/canceling login and signing out; same-origin remote Reader clients can read sanitized signed-in/plan-enabled status and current account model catalog, with account identifiers/emails and credential mutations kept host-only. It opens the Mac system browser and provides a link fallback for terminal/HTML clients. Remote Reader origins can use authorized document chat but cannot operate host authentication. A separate ephemeral 127.0.0.1 callback listener owns OAuth state; the normal Reader origin does not accept callback codes. Registration persists the issued client ID with the verified subject and supports saved registration selection. New credentials become active only after validation. Credentials never enter document history or browser storage; authorization URLs omit ID-token hints.

Requests use `store:false`, `stream:true`, full local completed history and no `previous_response_id`. Tools are function tools grouped in the `current_document` namespace. Hosted MCP, file_search and tool_search are absent; app-server local MCP/functions are a distinct supported capability, not a hosted-MCP workaround. Model choices come from the signed-in account's `/v1/models`; catalog presence is not entitlement proof. Only a successful user-initiated live turn can verify plan/model access, which remains pending.

`search_current_document` performs bounded literal accepted-passage search, and `read_passage` lists/reads accepted passage keys with pagination. Every call carries the accepted document/revision identity and checks the captured source fingerprint; neither accepts a path or command. Per-request limits remain 8000 selected/question characters, 20 search/list results and 8000 characters per passage page. Document exploration has no cumulative model-round, document-call or tool-output character limit. ResponsesProvider continues the same turn until a normal text answer or the existing cancellation, document/source change or upstream failure path. Every continuation retains the complete response output and each call_id/result, without forced final requests, automatic question resends or silent history deletion/summarization. Local history is authoritative; a 120000-character history budget rejects further turns honestly instead of deleting history. The initial excerpt is not the only accessible context.

### 6. 대화 요약과 사용자 인터랙션

- **요약 정책**: 접힌 한 줄 요약은 현재 대화 내용을 충실히 반영해야 하며 사실을 왜곡하거나 날조해서는 안 된다. 단순히 첫 번째 답변만 기계적으로 추출하도록 제약하지 않으며, 구체적인 요약 생성 알고리즘은 오픈 상태로 둔다.
- **키보드 및 터치 지원**: 키보드 `Enter`/`Space`로 요약을 열고, `Escape`로 닫고 원래 포커스로 복귀할 수 있어야 하며, 터치 디바이스 인터랙션을 지원한다.
- **선택 하이재킹 방지**: 문단 주변이나 내부 텍스트 선택 시 대화 UI가 포커스를 가로채거나 선택 수명주기를 방해하지 않는다.

## Risks / Trade-offs

- **국소 여백 탐색 실패와 인라인 폴백**: 복잡한 다단 수식이나 좁은 뷰포트에서 국소 여백을 찾지 못할 경우 잦은 인라인 폴백이 발생할 수 있으며, 이때 읽기 흐름의 일관성을 유지해야 한다.
- **OAuth 토큰 공유 및 모델 가용성**: 사용자 계정 유형이나 플랜 제한에 따라 토큰 공유 및 특정 모델 호출이 제한될 수 있으므로, 인증 실패 시 명확한 피드백과 안전한 폴백 처리가 필요하다.
- **활성 변경 간 레이아웃 충돌**: `add-responsive-reader`와 병렬 개발되는 과정에서 CSS 토큰 및 측정 로직이 중복되거나 충돌할 위험이 있으므로 구현 전 통합 조정이 필수적이다.

## Delivery and validation

Approval 1.1 is complete. HTML and terminal replace Saved for Codex with Ask, reuse selection capture and source verification, and share the same composer, host store and transport. Paged retains its legacy saved-context action until a follow-up adapter and remote Rust verification; no local Rust compilation is authorized.

One conversation per uniquely resolved paragraph; UUID conversation IDs are independent from service IDs and DOM nodes. Existing project-root/entry-path hashing gives restart stability and deliberate rename/move isolation. SQLite transactions serialize host history, drafts, message states and optimistic view versions across processes; 0700 directories and 0600 files live under `~/Library/Application Support/Lagrangian/paragraph-chat`, outside the source project. A lost host turn remains interrupted, never silently retried. User drafts survive failed and interrupted responses; retry is explicit and local history retains failed partials.

Reattachment compares complete accepted paragraph text with adjacent paragraph hashes (and same-revision key evidence), preserving source correspondence as private evidence. A changed or ambiguous paragraph is unresolved rather than guessed; users can open its saved history in the unresolved area. Exact-source fingerprints guard each opening and model-tool read.

Summary policy extracts the latest actual question and actual answer text with explicit partial/failure status; it makes no generated summary claims. Summary geometry measures actual ink near the paragraph, crosses the reading edge exactly by one-third, and falls back inline. Expanded conversations always follow their paragraph in flow. Long annotation/footnote columns move left into local whitespace and a narrow margin with mirrored connector routing; short labels retain their existing owner. No chat connector or count marker is added.

Focused Python/Node tests and a synthetic accepted-document real-browser fixture use temporary private stores, fake signed OAuth/JWKS and local HTTP/SSE Responses. Full reader lint, architecture, service and reader gates are required. No tests may sign in a real user, perform paid inference, install/restart services or compile Rust locally.

## Explicit pending coverage

- Real user-initiated OAuth registration/consent, live model entitlements, quotas, production key rotation and network revocation.
- Paged adapter with native selection protocol and remote Rust validation.
- Physical phone/tablet and native terminal device coverage; synthetic Chromium coverage is not device validation.

## Selection and acknowledgment correctness

Reopening a different subpassage in the same uniquely attached paragraph updates the current composer quote/context and its optimistic version while retaining the conversation ID. Each user message freezes a deep copy of its own verified selection, source evidence and accepted revision. Provider history pairs each user question with that message's original document context; the current turn uses the newest user message's frozen context. The UI refreshes its blockquote on reopening and displays each historical question's selected passage and revision. A changed selection is rejected while the conversation is streaming; users must wait or explicitly interrupt, then reselect. The active run never observes a replacement composer context.

Send message identities are deduplicated against stored questions before optimistic view-version checks, after service/document/revision validation. Reusing an identity for different question text is rejected. A failed acknowledgment triggers an authoritative history read; if the original message exists, the view recovers it without another send. A completed recovered question clears only its matching local draft, preserving any newer text. Python and Chromium regressions cover reselection, immutable history, running-context protection and a completed host turn whose HTTP acknowledgment is deliberately lost.

## Review hardening

Every GET/POST requires an exact Host allowlist: the bound 127.0.0.1/localhost port or the explicitly configured HTTPS Reader publicURL passed by the manager via --public-url (never the paged originalURL). Account login/logout/cancel additionally reject Forwarded, X-Forwarded-For, X-Forwarded-Host and every Tailscale-\* header. A random per-start host capability is written only to a 0600 local file in the private chat directory and removed on normal shutdown. HTTP never returns the capability, including to requests that forge local Host/Origin and hide forwarding headers. The local account status names the file; the host user explicitly pastes its capability value into a visually masked text field with autocomplete, spellcheck and autocapitalization disabled, retained only in controller memory. Comparisons use hmac.compare_digest. Capabilities and OAuth tokens never enter logs or browser storage.

OAuth callback exchange and signature verification run outside the state mutex. A generation check prevents an in-flight callback from saving credentials after cancellation, logout or a newer login. Cross-process credential transactions still serialize rotating refresh; an omitted or empty refreshed refresh_token retains the prior refresh token. ID tokens are verified for login and then discarded, including unverified refresh ID tokens. Cancellation closes the upstream Responses response, waking a blocked SSE socket before close so provider work is released promptly.

The unused HTML CodexContextController and public asset are removed. GET/POST /api/focus and services/codex_context.py remain a compatibility protocol for external saved-focus clients and existing focus-file consumers; they are not invoked by Ask or authoritative chat history. The route's storage failure message uses reader-focus terminology.

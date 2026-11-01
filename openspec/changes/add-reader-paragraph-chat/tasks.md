# Tasks

사용자 승인과 수정사항을 수락했다(2026-11-01). 1.1 단일 승인 게이트 완료; 추가 승인 요청 없음. HTML+terminal 공통 구현이 1차 전달 범위이며 paged와 실계정 검증은 별도 후속 항목이다.

## 1. 사전 조사 및 승인 게이트

- [x] 1.1 사용자 검토 및 제안서 승인 게이트: 제안서와 설계를 검토받고 구현 착수 여부를 단일 게이트로 승인받는다.
- [x] 1.2 활성 변경 통합 조정: 활성 변경 `add-responsive-reader`와의 레이아웃/구분선/어노테이션 배치 충돌 지점을 분석하고 구현 및 아카이브 전 조정 계획을 확정한다.
- [x] 1.3 OpenAI SIWC/Codex 공식 문서 검토 및 격리 프로토콜 검증: 제안서 승인 후 공식 문서를 검토하고 로컬 fake OAuth/JWKS/Responses로 갱신·폐기·도구 제한을 검증하여 제품 결정을 기록한다(실제 사용자 OAuth/모델 적격성은 6.1에 명시적으로 남김).
- [x] 1.4 토큰 라이프사이클 및 전송 경로 결정: 호스트 서비스 내 안전한 토큰 보관/갱신/폐기 책임과 직접 Responses API vs Codex app-server 전송 중 1차 경로를 확정한다.
- [x] 1.5 기존 선택·주석 코드 재사용 및 영향 분석: `reader-common/selection/submission.js`, `flow_reader/services/selection.py`, `web/rendering/annotations.js`의 기존 동작을 점검한다.
- [x] 1.6 핵심 제품 설계 결정 확정: 초기 릴리스 대상 뷰어 범위(HTML 전용 vs terminal·paged), 문서 이동/이름 변경 시 지속 문서 신원 체계, 문단당 단일 vs 복수 대화 스레드 및 문맥 예산을 확정한다.

## 2. 호스트 서비스 및 지속 저장소

- [x] 2.1 대화 레코드 스키마 정의: `conversation_id`, `document_id`, `revision`, `quote`, `context`, `thread`, `anchor_evidence` 필드를 포함한 데이터 구조를 `flow_reader/services/paragraph_chat.py`에 정의한다.
- [x] 2.2 비공개 호스트 로컬 저장소 구현: 소스 저장소 외부의 안전한 경로에 문서별 대화 기록을 격리 저장하고 조회하는 지속성 로직을 작성한다.
- [x] 2.3 서비스 재시작 지속성 및 메타데이터 분리: `service_id`는 요청 메타데이터로 취급하고 서비스 재시작 후에도 안정적인 문서 ID로 대화를 복원하도록 보장한다.
- [x] 2.4 결합 증거 기반 앵커 재부착: 단순 인용문 횟수가 아닌 문서 신원, 인용문, 문맥 증거를 결합해 유일 일치 시에만 재부착하고 모호/삭제 시 미해결 상태로 보존한다.
- [x] 2.5 Provider 인증 및 전송 경계 주입: 서비스 경계 내에 provider 브리지를 주입하고 범용 프레임워크 없이 단일 인증/전송 계층을 구성한다.
- [x] 2.6 보안 경계 검증: 브라우저 응답, 로컬 대화 파일, 로그, 소스 저장소에 토큰 및 비밀값이 유출되지 않도록 가드를 둔다.
- [x] 2.7 HTTP 라우팅 및 비동기 전송: `server/http.py`에 대화 생성, 조회, 후속 질문, 스트리밍 엔드포인트를 추가하고 리비전 불일치 응답 폐기를 구현한다.

## 3. Reader 프론트엔드 어댑터

- [x] 3.1 선택 연동 및 명시적 전송: 문단/구절 선택 후 명시적 액션으로만 질문이 전송되도록 제어하고 텍스트 선택 하이재킹을 방지한다.
- [x] 3.2 키보드 및 터치 인터랙션: Enter/Space로 열기, Escape로 닫기 및 포커스 복귀, 터치 활성화를 지원한다.
- [x] 3.3 스트리밍 응답 렌더링: 토큰 스트리밍 진행 표시, 중복 전송 방지, 중단/실패 시 초안 및 이전 메시지 보존을 구현한다.
- [x] 3.4 접힌 한 줄 요약 및 인라인 확장: 문단 인근 요약 말풍선 표시, 클릭 시 연관 문단 바로 아래 flow로 대화 확장, 후속 질문 반영을 구현한다.
- [x] 3.5 다중 문단 독립 대화 관리: 동일 문서 내 여러 문단의 대화가 서로 간섭하거나 결합되지 않도록 독립 상태를 유지한다.
- [x] 3.6 미해결/고아 대화 시각화: 앵커가 모호하거나 문단이 삭제된 대화를 임의 재배치하지 않고 상태를 정직하게 표시한다.
- [x] 3.7 신규 프론트엔드 자산 등록 및 설치 번들 검증: `web/assets.json`에 신규 자산을 등록하고 패키징된 설치 번들 레이아웃과 전달을 검증한다.

## 4. 기하 및 레이아웃 통합

- [x] 4.1 w/3 + 2w/3 여백 배치: w/3은 본문 인라인 빈 공간, 2w/3은 축소된 우측 여백에 배치하고 잉크 및 수식 겹침을 방지한다.
- [x] 4.2 세로 위치 탐색 및 인라인 폴백: 문단 인근의 유효한 국소 여백을 탐색하고 여백 부족 시 문단 직하 인라인 흐름으로 폴백한다.
- [x] 4.3 테마 및 단일 배경: 본문과 여백에 동일 배경(`--paper`)을 유지하고 구분선 및 중복 마커(숫자 배지, 사이드바 아이콘)를 배제한다.
- [x] 4.4 주석/각주 레이아웃 재배치: 본 기능 활성화 시 긴 주석/각주를 좌측 좁은 여백 및 국소 빈 공간으로 이동하고 지시선을 유지하며 노트 구분선을 제거한다.
- [x] 4.5 뷰포트 및 글꼴 재계산: 윈도우 리사이즈 및 글꼴 크기 변경 시 읽기 위치를 유지하며 기하 측정을 갱신한다.

## 5. 테스트 및 검증

- [x] 5.1 Python 지속성 및 서비스 단위 테스트: `yarn test:reader-services`를 통해 문서별 격리, 서비스 재시작 후 복원, 비밀값 비노출, 리비전 가드를 검증한다.
- [x] 5.2 Node 프론트엔드 정책 테스트: `node --test`로 요약 생성, 스트리밍 상태 전이, 키보드/터치 정책, 다중 문단 격리를 검증한다.
- [x] 5.3 실제 브라우저 기하 및 레이아웃 검증: w/3 + 2w/3 측정, 인근 여백 탐색, 인라인 폴백, 잉크 비침범, 기존 주석 지시선 유지/구분선 제거를 확인한다.
- [x] 5.4 기존 어노테이션 회귀 방지 테스트: 짧은 mannot 수식 근접 위치, 표준 복사/선택, ID/번호 보존이 깨지지 않음을 확인한다.
- [x] 5.5 Reader 린트 및 아키텍처 게이트: `yarn lint:readers`, `yarn test:readers`, `yarn test:architecture`를 실행해 린트 통과와 기능 소유권 경계를 검증한다. 실행 완료: lint/architecture 통과, 전체 reader 서비스 검사는 Neovim RPC 오류 1건 및 sandbox의 ps 실행 거부 2건으로 실패(286개 중 58개 선택 통합 테스트 건너뜀); paged 98개/DOM 37개는 별도 통과. 전체 게이트 통과는 아직 미검증.
- [x] 5.6 문서 갱신 및 준비: canonical architecture/terminal Typst 문서에 소유권과 사용 흐름을 반영하고 컴파일한다. 해당 정본의 Markdown 생성 매핑은 없으며 관련 없는 생성물은 유지한다.

## 6. Explicit follow-up coverage

- [ ] 6.1 **NOT YET VERIFIED (live OAuth):** User-initiated real OAuth consent and live model/plan/quota entitlements, production key rotation and remote revocation; never run without user initiation.
- [ ] 6.2 **NOT YET VERIFIED:** Paged selection/chat adapter and native protocol integration with remote Rust builds; excluded from HTML+terminal primary delivery.
- [ ] 6.3 **NOT YET VERIFIED:** Physical phone/tablet and native terminal device checks; synthetic browser coverage does not complete this item.

## Verification evidence

Focused fake OAuth/Python: 14 passed. Synthetic Chromium: 28 checks, zero browser errors, including two subpassages in one conversation, immutable message context, rejected streaming reselection and completed-turn lost-ack recovery. Literal summary/snapshot/geometry Node tests, lint and architecture passed. Full reader gate results and detailed logs live under `/tmp/reader-paragraph-chat-logs`; all auth/model traffic in these fixtures is fake and local. Screenshot: `/tmp/reader-paragraph-chat-logs/chat-wide.png` (synthetic accepted document, fake model data).

Architecture and terminal Typst compile successfully. `yarn docs:check` reports the pre-existing unrelated README Markdown drift; README.md/docs/dev-guide.md were restored after the generator inspection and remain untouched. Compiler/source-history integration prerequisites are not provisioned, so the base reader gate's optional skips do not constitute actual compiler or device coverage. No repository commit/push, Rust build, live OAuth/inference or live service install/restart was performed.

Final full-gate evidence: Node 270 passed; Python 279 ran with 58 optional skips and one unchanged Neovim timing assertion failure (`test_late_remote_capability_reply_starts_reader`, 3 capability queries vs expected 2). Its isolated retry passed (1/1). Changed chat tests all passed in the full run. Separately rerun paged Vitest 98 and DOM Vitest 37 passed. Item 5.5 remains unchecked for a fully green final aggregate run; its lint and architecture checks passed. No Neovim timing code/test was changed to mask the unrelated failure.

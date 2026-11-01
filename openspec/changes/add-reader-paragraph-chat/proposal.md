# Proposal

## Why

Reader에서 문단을 읽다 생긴 질문은 지금 Reader 밖으로 나가야 하고, 받은 답을 그 문단과 다시 연결할 방법이 없다.
Saved for Codex는 선택 문맥을 저장만 하고 메시지를 보내지 않으므로, 읽던 자리에서 질문하고 그 답을 문서에 남기는 흐름이 비어 있다.

## What Changes

- Reader 안에서 문단이나 구절을 선택하고 질문을 **명시적으로** 보내면 답변이 스트리밍으로 표시된다.
- 대화는 소스 저장소 외부의 비공개 호스트 로컬 저장소에 문서별·문단별로 저장되며, 서비스 재시작이나 페이지 재오픈 후에도 안정적인 문서 ID를 통해 유지된다.
- 접힌 한 줄 요약(현재 대화 내용을 반영하며 사실을 왜곡하지 않음)이 해당 문단 인근에 나타나고, 확장하면 연관 문단 바로 아래 흐름(in flow directly below associated paragraph)에서 대화가 펼쳐진다.
- 말풍선 가로 배치는 적격한 넓은 화면에서 정확히 w/3이 본문 읽기 컬럼 안쪽 빈 공간에, 2w/3이 축소된 오른쪽 페이지 여백에 놓이며 잉크·수식·주석을 덮지 않는다. 세로 배치는 경직된 첫 줄 맞춤 대신 문단 인근의 유효한 국소 빈 공간을 먼저 탐색하고 여백 부족 시 인라인 폴백으로 전환한다.
- 페이지 전체와 좌우 여백은 구분선 없는 같은 배경을 쓰고, 숫자 배지나 사이드바 말풍선 아이콘을 중복 표시하지 않는다.
- 본 기능 레이아웃이 활성화될 때, 활성 변경인 `add-responsive-reader`의 'Connected local side columns' 및 'Viewport and text-size changes' 시나리오의 배치·구분선 측면을 대체한다(긴 주석/각주는 사용 가능한 국소 여백과 좁은 왼쪽 여백으로 이동, 구분선 제거, 유의미한 연결 지시선 유지, 짧은 mannot은 수식 근접 유지, 표준 본문/번호/ID/복사/컴팩트 팝오버 보존).
- 비밀값(자격 증명, 토큰)은 브라우저 응답/저장소, 대화 기록, 소스 저장소, 로그에 남기지 않는다. 호스트 서비스가 지속 대화와 앵커 증거를 소유하며, 단일 OAuth 인증 아래 직접 SIWC OAuth + Responses SSE 전송 브리지를 주입받는다(범용 provider 프레임워크 없음, HTTP 라우트는 전송만 담당).
- HTML과 terminal의 기존 Saved for Codex UI 동작을 Ask/문단 대화로 교체한다. 선택 캡처와 승인된 소스 검증은 재사용한다. 기존 focus 읽기/저장 프로토콜은 호환성용으로 남고 대화의 권위가 되지 않는다.
- 첫 전달 범위는 HTML+terminal 공통 구현이다. paged 어댑터는 Rust 원격 검증을 갖춘 후속 작업이며 이번 구현 완료 주장에 포함하지 않는다.
- 초기에는 문단당 대화 하나를 사용한다. 프로젝트 루트/엔트리 경로 기반 문서 ID는 재시작에 안정적이며 rename/move를 조용히 병합하지 않는다. 미해결 기록은 별도 접근 가능한 영역에 보존한다.
- 모델은 초기 선택 외에도 승인 스냅샷에 한정된 search_current_document/read_passage 도구로 필요한 문맥을 페이지 단위로 추가 조회한다.

## Capabilities

### New Capabilities

- `reader-paragraph-chat`: Reader 안에서 문단·구절 단위로 질문하고, 문서에 귀속된 지속 대화 기록을 흐름 안에서 다시 열람·후속 질문하며, 안전한 앵커·여백 배치·테마 연속성을 지키는 능력.

### Modified Capabilities

없음. 문단 대화가 활성화된 HTML/terminal의 주석 공존 규칙은 `reader-paragraph-chat`의 ADDED 요구사항으로 정의하며, `add-responsive-reader`는 수정하지 않는다.

## Impact

- `tools/flow-reader/web/features/`: 문단 대화 어댑터(선택 연동, 키보드/터치 탐색, 말풍선, 스트리밍 표시, 기록 열람).
- `tools/flow-reader/web/reader.css`: 레이아웃·여백·테마 토큰 확장(기존 토큰 값 유지, 잉크 비침범 기하).
- `tools/flow-reader/flow_reader/services/`: 대화 저장(소스 저장소 외부 호스트 로컬 저장소)·결합 앵커 증거·provider 전송 주입 경계.
- `tools/flow-reader/flow_reader/server/http.py`, `web/assets.json`: 새 서비스 경로와 정적 자산 등록.
- `docs/tinymist/dev/reader-architecture.typ`: 새 기능 소유자와 경계 기록.
- 테스트: Python 서비스 테스트(`yarn test:reader-services`), Node 프론트엔드 정책 테스트, 브라우저 기하 및 주석 회귀 테스트.

사용자는 2026-11-01 구현과 위 수정사항을 승인했다. 단일 승인 게이트 1.1은 완료이며 두 번째 승인을 요구하지 않는다. 실계정 로그인과 라이브 모델/플랜 적격성 검증은 사용자가 실제 sign-in을 시작할 때까지 미검증으로 남는다.

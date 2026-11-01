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
- 비밀값(자격 증명, 토큰)은 브라우저 응답/저장소, 대화 기록, 소스 저장소, 로그에 남기지 않는다. 호스트 서비스가 지속 대화와 앵커 증거를 소유하며, 단일 OAuth 인증 아래 직접 Responses API 및 Codex app-server 전송 브리지를 주입받는다(범용 provider 프레임워크 없음, HTTP 라우트는 전송만 담당).
- Saved for Codex의 저장 전용 계약은 변경하지 않는다.

## Capabilities

### New Capabilities

- `reader-paragraph-chat`: Reader 안에서 문단·구절 단위로 질문하고, 문서에 귀속된 지속 대화 기록을 흐름 안에서 다시 열람·후속 질문하며, 안전한 앵커·여백 배치·테마 연속성을 지키는 능력.

### Modified Capabilities

- 없음 (`none`): 현재 accepted specs(`openspec/specs/`)에는 `responsive-reader`가 아직 병합되지 않아 형식상 수정할 accepted capability가 없다. 그러나 활성 변경인 `add-responsive-reader`와의 통합 요구사항이 존재하며, 문단 대화 레이아웃 활성화 시 `add-responsive-reader`의 'Connected local side columns' 및 'Viewport and text-size changes' 시나리오의 배치·구분선 측면을 대체한다(긴 주석/각주는 국소 여백 및 좁은 왼쪽 여백으로 이동, 구분선 제거, 기존 지시선 유지, 짧은 mannot 수식 근접 유지, 표준 본문/번호/ID/복사/컴팩트 팝오버 보존). 구현 및 아카이브 전 두 활성 변경 간 조정을 수행한다.

## Impact

- `tools/flow-reader/web/features/`: 문단 대화 어댑터(선택 연동, 키보드/터치 탐색, 말풍선, 스트리밍 표시, 기록 열람).
- `tools/flow-reader/web/reader.css`: 레이아웃·여백·테마 토큰 확장(기존 토큰 값 유지, 잉크 비침범 기하).
- `tools/flow-reader/flow_reader/services/`: 대화 저장(소스 저장소 외부 호스트 로컬 저장소)·결합 앵커 증거·provider 전송 주입 경계.
- `tools/flow-reader/flow_reader/server/http.py`, `web/assets.json`: 새 서비스 경로와 정적 자산 등록.
- `docs/tinymist/dev/reader-architecture.typ`: 새 기능 소유자와 경계 기록.
- 테스트: Python 서비스 테스트(`yarn test:reader-services`), Node 프론트엔드 정책 테스트, 브라우저 기하 및 주석 회귀 테스트.

이 문서는 향후 구현 명세를 정의하며, 사용자 검토 및 제안서 승인 전까지는 실제 구현을 진행하지 않는 proposal 단계이다.

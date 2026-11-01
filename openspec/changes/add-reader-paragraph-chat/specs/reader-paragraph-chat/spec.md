# Spec Delta

## Purpose

Reader에서 읽던 문단이나 구절에 대해 묻고, 받은 답을 그 문단과 함께 다시 읽고 이어 묻는 문서 귀속 지속 대화 능력이다.

## ADDED Requirements

### Requirement: 문단 대화 요청과 스트리밍 답변

Reader는 사용자가 문단이나 구절을 선택하고 질문을 명시적으로 보낼 때만 대화를 시작해야 한다(SHALL). 선택, 스크롤, 탭만으로는 요청을 보내서는 안 된다(MUST NOT). 답변은 스트리밍으로 표시되고 요청과 답변은 해당 문단에 연결되어야 한다(MUST). 키보드, 터치 인터랙션을 온전히 지원해야 하며 사용자 텍스트 선택을 하이재킹해서는 안 된다(MUST NOT).

#### Scenario: 선택 후 질문 전송

- **WHEN** 사용자가 본문 문단이나 구절을 선택하고 질문을 입력해 전송한다
- **THEN** Reader는 선택된 인용문과 문맥을 담은 요청을 보내고 답변을 스트리밍으로 표시한다
- **AND** 요청과 답변은 그 문단에 연결된 대화로 기록된다

#### Scenario: 선택만으로는 전송되지 않음

- **WHEN** 사용자가 문단을 선택만 하고 질문을 입력하거나 전송하지 않는다
- **THEN** 어떤 provider 요청도 발생하지 않는다
- **AND** 선택과 기존 Saved for Codex 동작은 그대로 유지된다

#### Scenario: 스트리밍 중 표시

- **WHEN** 답변이 스트리밍되는 중이다
- **THEN** 말풍선은 진행 중임을 표시하고 현재까지의 텍스트를 보여 준다
- **AND** 전송 버튼은 중복 전송을 막고, 사용자의 스크롤과 선택을 빼앗지 않는다

#### Scenario: 선택 하이재킹 방지와 텍스트 선택 상호작용

- **WHEN** 사용자가 문단 내부 또는 주변의 텍스트를 드래그하여 선택하거나 복사한다
- **THEN** 대화 UI가 포커스를 강제로 가로채거나 브라우저 기본 선택 동작을 하이재킹하지 않는다
- **AND** 명시적으로 대화 입력이나 전송을 누르기 전까지 읽기 상태가 방해받지 않는다

#### Scenario: 키보드 및 터치 인터랙션

- **WHEN** 사용자가 키보드로 문단 대화 요약에 포커스한 후 Enter 또는 Space를 누르거나, 터치 화면에서 요약을 탭한다
- **THEN** 대화 내용이 즉시 펼쳐지고 입력 필드로 포커스가 이동한다
- **AND** Escape를 누르면 대화가 접히고 포커스는 직전 활성화 지점으로 안전하게 복귀한다

### Requirement: 문서별 지속 대화 기록과 서비스 재시작 영속성

Reader는 대화 기록을 문서 단위로 소스 저장소 외부의 비공개 호스트 로컬 저장소에 저장해야 하며(SHALL), 다시 열거나 서비스가 재시작되어도 유지되어야 한다(MUST). 기록은 문단별 스레드로 구분되고 동일 문서 내 서로 다른 문단이나 다른 문서의 기록과 섞여서는 안 된다(MUST NOT).

#### Scenario: 다시 열기

- **WHEN** 사용자가 대화가 있는 문서를 닫았다가 다시 연다
- **THEN** 같은 문단의 대화가 요약으로 다시 표시되고 펼치면 이전 질문과 답변이 순서대로 나타난다

#### Scenario: 동일 문서 내 독립된 문단 대화 격리

- **WHEN** 사용자가 동일한 문서 안의 문단 A와 문단 B에서 각각 개별적인 대화를 시작한다
- **THEN** 두 문단은 완전히 분리된 독립 대화 기록을 유지한다
- **AND** 문단 A에 후속 질문을 보내도 문단 B의 대화와 결합되거나 문단 B의 기록을 변경하지 않는다

#### Scenario: 서비스 재시작 후 지속성과 메타데이터 분리

- **WHEN** 대화가 저장된 후 Reader 백엔드 서비스 프로세스가 재시작된다
- **THEN** Reader는 안정적인 문서 식별자를 통해 기존 대화 기록을 유실 없이 복원한다
- **AND** 저장 시점의 서비스 인스턴스 ID(`service_id`)는 요청 메타데이터로만 취급되며 지속적인 문서 신원을 대체하거나 무효화하지 않는다

#### Scenario: 다른 문서와의 격리

- **WHEN** 같은 서비스에서 다른 문서를 연다
- **THEN** 이전 문서의 대화는 표시되지 않고 새 문서의 기록만 나타난다
- **AND** 두 문서의 기록 저장 위치는 서로 덮어쓰지 않는다

### Requirement: 안정적인 대화 식별자와 결합 앵커 증거

각 대화는 DOM 노드 신원이나 최신 Saved for Codex 포커스 기록과 무관한 안정적인 대화 ID를 가져야 한다(SHALL). 대화는 단순 인용문 일치 횟수에만 의존하지 않고 문서 신원, 인용문, 사용 가능한 경우 문맥 및 소스 오프셋을 결합한 유일 증거를 통해 재부착되어야 한다(MUST).

#### Scenario: 결합 증거에 기반한 유일 재부착

- **WHEN** 문서가 다시 렌더링되어 대화를 문단에 다시 붙인다
- **THEN** Reader는 문서 신원, 인용문, 문맥 증거를 결합해 정확히 유일하게 일치하는 문단에만 대화를 재부착한다
- **AND** 단순 인용문 횟수에 의존하지 않고 그 결과를 앵커 증거로 기록한다

#### Scenario: 독립적인 신원

- **WHEN** 다른 선택이 Saved for Codex 포커스 기록을 갱신하거나 DOM이 교체된다
- **THEN** 기존 대화 ID와 그 기록은 변경되지 않는다

### Requirement: 모호하거나 사라진 앵커의 보존

앵커가 모호하거나 사라졌을 때 Reader는 기록을 삭제하거나 다른 문단에 조용히 재배치해서는 안 된다(MUST NOT). 재부착되지 않은 대화는 미해결 상태로 보존되고 명시적으로 표시되어야 한다(SHALL). 미해결 대화는 별도의 접근 가능한 unresolved 영역에서 보존하고 열람할 수 있어야 한다(SHALL).

#### Scenario: 모호한 앵커

- **WHEN** 보존된 인용문과 결합 증거가 현재 문서에서 둘 이상의 위치에 대응하여 유일성을 판정할 수 없다
- **THEN** Reader는 임의의 한 위치를 고르지 않고 대화를 미재부착 상태로 남긴다
- **AND** 사용자는 기록을 잃지 않고 그 상태를 확인할 수 있다

#### Scenario: 삭제된 문단과 미해결 상태 보존

- **WHEN** 저장된 대화의 원본 문단이 문서 편집이나 삭제로 완전히 사라졌다
- **THEN** Reader는 대화 기록을 보존하고 미해결(unresolved) 상태로 표시한다
- **AND** 별도의 접근 가능한 unresolved 영역에서 기록을 열람할 수 있고 인접 문단에 임의 재배치되지 않는다

### Requirement: 문서·선택 안전 비동기 답변과 초안 보존

비동기 답변은 현재 문서·서비스·리비전과 요청 당시 선택을 확인한 뒤에만 게시되어야 한다(SHALL). 늦게 도착한 답변이 다른 문서나 새 선택 위에 그려져서는 안 된다(MUST NOT). 인증 실패나 연결 중단 시에도 기존 기록과 작성 중인 초안은 보존되어야 하며 사실대로 표시되어야 한다(MUST). 허위나 가짜 답변을 지어내서는 안 된다(MUST NOT).

#### Scenario: 리비전이 바뀐 뒤 도착한 답변

- **WHEN** 요청 이후 문서 리비전이 바뀌었거나 서비스가 교체된 상태에서 답변이 도착한다
- **THEN** Reader는 현재 문서나 선택 위에 그 답변을 그리지 않는다
- **AND** 해당 대화는 원래 리비전의 기록으로 남고 사용자에게 상태가 알려진다

#### Scenario: 중단된 스트리밍과 초안 보존

- **WHEN** 스트리밍이 네트워크 오류, 취소, 또는 인증 실패로 중단된다
- **THEN** 말풍선은 실패 상태를 사실대로 표시하고 부분 텍스트나 가짜 답변을 완성된 응답으로 꾸며내지 않는다
- **AND** 이미 기록된 대화 메시지와 사용자가 작성 중이던 입력 초안은 유실되지 않고 재시도할 수 있다

### Requirement: 흐름 안의 접힌 요약과 연관 문단 직하 확장

대화는 해당 문단 인근 읽기 흐름 안에 접힌 한 줄 요약으로 표시되어야 한다(SHALL). 요약은 현재 대화 내용을 반영해야 하며 사실을 왜곡하거나 날조해서는 안 된다(MUST NOT). 요약 생성 알고리즘은 오픈 상태로 두며 첫 번째 답변만으로 제한하지 않는다. 확장 시에는 연관 문단 바로 아래 흐름(in flow directly below associated paragraph)에서 대화가 펼쳐져야 한다(MUST).

#### Scenario: 요약과 확장

- **WHEN** 대화가 있는 문단을 지난다
- **THEN** 접힌 한 줄 요약 말풍선이 해당 문단 인근 흐름 안에 표시된다
- **AND** 요약은 현재 대화 내용을 충실히 반영하며 첫 답변 추출에만 한정되지 않는다
- **AND** 요약을 활성화하면 연관 문단 바로 아래 흐름에서 질문·답변 목록이 펼쳐지고 다시 접을 수 있다

#### Scenario: 후속 질문과 요약 갱신

- **WHEN** 펼친 대화에서 사용자가 후속 질문을 보낸다
- **THEN** 질문과 답변이 같은 문단 스레드에 추가된다
- **AND** 요약은 갱신된 전체 대화 내용을 반영하여 업데이트된다

### Requirement: 말풍선 여백 배치와 인근 여백 탐색

폭 w인 말풍선은 적격한 넓은 화면에서 정확히 w/3을 본문 읽기 컬럼 안쪽 빈 공간에, 2w/3을 축소된 오른쪽 페이지 여백에 두어야 한다(MUST). 본문 글자, 수식, 수식 번호, 주석을 덮어서는 안 되며(MUST NOT), 세로 위치는 경직된 첫 줄 맞춤 대신 문단 인접 국소 빈 공간을 먼저 탐색하고 여백 부족 시 인라인 폴백을 사용해야 한다(MUST).

#### Scenario: 1/3 기하 검증

- **WHEN** 적격한 넓은 화면에서 문단 옆에 말풍선이 배치된다
- **THEN** 말풍선 폭 w에 대해 컬럼 안쪽 빈 공간에 놓인 부분은 w/3, 오른쪽 페이지 여백으로 넘어간 부분은 2w/3이다
- **AND** 두 비율은 측정 오차 범위 안에서 일치하고 본문 글자, 수식, 주석 등 기존 잉크와 절대 겹치지 않는다

#### Scenario: 국소 여백 탐색과 인라인 폴백

- **WHEN** 대상 문단의 첫 행 여백이 비어 있지 않거나 수식 등이 인접해 있다
- **THEN** Reader는 경직되게 첫 줄에 고정하지 않고 문단에 인접한 국소 빈 공간을 탐색하여 말풍선을 배치한다
- **AND** 주변 여백이 모두 부족하거나 화면 폭이 미달하면 말풍선을 압축하지 않고 연관 문단 직하 인라인 흐름으로 전환한다

### Requirement: 페이지 배경과 마커의 단일성

전체 페이지와 좌우 여백은 사이드바 구분선 없이 같은 배경을 사용해야 한다(SHALL). 숫자 배지나 사이드바 말풍선 아이콘을 중복 표시해서는 안 된다(MUST NOT). 말풍선 자체가 한 줄 요약을 담당하고 현재 테마의 절제된 스타일을 사용할 수 있다.

#### Scenario: 배경과 구분선

- **WHEN** 대화가 있는 문서를 넓은 화면에서 본다
- **THEN** 본문과 좌우 여백은 이어진 같은 배경으로 보이고 사이드바를 나누는 세로 구분선이 없다

#### Scenario: 마커 중복 없음

- **WHEN** 한 문단에 대화가 하나 이상 있다
- **THEN** 문단 옆에는 요약 말풍선만 나타나고 별도의 숫자 배지나 독립된 말풍선 아이콘이 함께 나타나지 않는다

### Requirement: 기존 주석과의 병존 및 responsive-reader 대체 규칙

본 기능 레이아웃이 활성화될 때, 활성 변경인 `add-responsive-reader`의 'Connected local side columns' 및 'Viewport and text-size changes' 시나리오의 배치·구분선 측면을 대체해야 한다(SHALL). 계획된 긴 주석과 각주는 사용 가능한 국소 빈 공간과 좁은 왼쪽 여백으로 이동하고 노트 영역 구분선을 제거하되 유의미한 연결 지시선은 유지해야 한다(MUST). 짧은 mannot 표기는 수식 인근에 그대로 유지되고(MUST), 기존의 표준 본문 내용, 번호, ID, 복사 텍스트, 컴팩트 팝오버는 보존되어야 한다(MUST).

#### Scenario: responsive-reader 배치 및 구분선 대체

- **WHEN** 문단 대화 레이아웃 기능이 활성화된 상태에서 문서를 렌더링한다
- **THEN** `add-responsive-reader`의 사이드 컬럼 구분선이 제거되고 본문과 동일한 배경이 유지된다
- **AND** 긴 주석과 각주는 국소 여백 및 좁은 왼쪽 여백으로 이동하되 대상과의 연결 지시선은 그대로 유지된다
- **AND** 기존의 표준 본문 텍스트, 수식 번호, 앵커 ID, 복사 텍스트 및 컴팩트 팝오버는 변경 없이 보존된다

#### Scenario: 수식 옆 주석과 대화

- **WHEN** 짧은 mannot 표기가 있는 수식 문단에 대화도 존재한다
- **THEN** 짧은 mannot 표기는 수식 인근 라벨 위치를 유지하고 대화는 별도 여백에 배치되어 서로 덮지 않는다
- **AND** 긴 주석과 각주는 왼쪽 여백과 국소 공간을 활용하여 오른쪽 여백의 대화와 간섭하지 않는다

#### Scenario: 대화 요약에 연결선 없음

- **WHEN** 대화 요약이 문단 인근에 표시된다
- **THEN** 요약과 문단을 잇는 지시선이나 점 표시가 그려지지 않는다
- **AND** 기존 주석 연결선의 모양과 의미는 유지된다

### Requirement: 테마와 타이포그래피 연속성

대화 표면은 현재 `reader.css` 토큰과 다크 모드 토큰 동작, 본문 타이포그래피, 툴바를 따라야 한다(SHALL). 따뜻한 종이 `#faf9f6`, 잉크 `#292824`, 보조 텍스트 `#6b6962`, 강조 `#35675d` 값과 다크 모드 대응을 바꾸어서는 안 된다(MUST NOT).

#### Scenario: 테마 전환

- **WHEN** 사용자가 밝은 테마와 어두운 테마를 전환한다
- **THEN** 요약과 펼친 대화가 현재 테마 토큰으로 다시 그려지고 본문과 이질적인 색을 쓰지 않는다

#### Scenario: 글자 크기와 툴바

- **WHEN** 사용자가 읽기 글자 크기를 바꾸거나 툴바를 사용한다
- **THEN** 대화 표면은 본문 타이포그래피 체계를 따르고 기존 툴바 배치와 겹치지 않는다

### Requirement: 로컬 기록의 권위와 Ask 동작으로의 교체

Reader의 로컬 대화 기록이 권위 있는 기록이어야 하며(SHALL), 기존 ChatGPT 대화나 메모리를 가져오지 않아야 한다(MUST NOT). HTML과 terminal의 Saved for Codex UI는 Ask로 교체되어야 한다(MUST). 기존 선택 캡처 및 승인 소스 검증은 재사용되어야 한다(SHALL). paged 어댑터는 명시적인 후속 범위이다.

#### Scenario: 가져오기 없음

- **WHEN** 사용자가 처음으로 문단 대화를 연다
- **THEN** Reader는 외부 계정의 과거 대화나 메모리를 가져오지 않고 로컬 기록만 사용한다

#### Scenario: 명시적 Ask와 Send

- **WHEN** HTML 또는 terminal에서 기존 저장 액션 자리에 있는 Ask를 활성화한다
- **THEN** 검증된 선택 문맥으로 문단당 하나의 대화를 열고 작성기를 표시한다
- **AND** 사용자가 Send를 누르기 전에는 모델 턴을 시작하지 않는다
- **AND** 기존 focus 프로토콜은 호환성으로 남아도 대화 기록을 대체하지 않는다

#### Scenario: 필요한 추가 문맥 조회

- **WHEN** 모델이 선택 외의 문서 문맥을 필요로 한다
- **THEN** 승인된 현재 문서와 리비전에 한정된 search_current_document/read_passage 함수를 페이지 단위로 호출할 수 있다
- **AND** 임의 파일 경로, 셸, 외부 문서, hosted MCP/file_search/tool_search는 제공되지 않는다

#### Scenario: rename과 restart

- **WHEN** 서비스만 재시작한다
- **THEN** 같은 프로젝트 루트와 엔트리 경로의 대화는 복원된다
- **AND** 경로 이름 변경이나 이동은 이전 문서 기록과 조용히 병합되지 않는다

### Requirement: 호스트 소유 자격 증명, 비공개 로컬 저장소 및 전송 경계

자격 증명과 비밀값은 브라우저 응답/저장소, 대화 기록, 소스 저장소, 로그에 남겨서는 안 된다(MUST NOT). 대화 본문은 소스 저장소 외부의 비공개 호스트 소유 로컬 저장소에 저장되어야 한다(SHALL). 호스트 서비스는 단일 OAuth 인증 아래 직접 Responses API 전송과 Codex app-server 전송 중 하나를 선택하여 주입받을 수 있어야 한다(MUST).

#### Scenario: 비밀값 격리와 소스 저장소 외부 로컬 저장

- **WHEN** 대화가 생성되고 호스트 서비스에 지속 보존된다
- **THEN** 브라우저 로컬 스토리지, 세션 스토리지, 쿠키, 소스 저장소 파일, 콘솔 로그 어디에도 토큰과 자격 증명이 저장되거나 노출되지 않는다
- **AND** 대화 본문은 소스 코드 저장소 외부의 안전한 비공개 호스트 로컬 저장소에만 보존된다

#### Scenario: 인증 실패 시 초안 보존과 진실된 상태 표시

- **WHEN** 호스트에 유효한 OAuth 자격 증명이 없거나 만료되어 요청이 실패한다
- **THEN** Reader는 허위 답변을 생성하지 않고 인증이 필요하다는 실패 상태를 사실대로 표시한다
- **AND** 사용자가 작성 중이던 초안과 이전 대화 기록은 유실 없이 안전하게 보존된다

#### Scenario: 검증된 OAuth 접근과 전송 실행

- **WHEN** 구성된 호스트 provider가 적격한 OAuth 접근 권한을 확인하고 요청을 처리한다
- **THEN** 요청된 질문은 선택된 전송 경로(직접 Responses API 또는 Codex app-server 중 하나, 두 전송 모두 구현할 의무는 없음)와 Reader 소유의 로컬 대화 기록을 사용한다
- **AND** 인증이나 모델을 사용할 수 없는 경우 가짜 답변을 생성하거나 기존 대화 기록을 지우지 않고 실패 상태를 눈에 띄게 표시한다

### Requirement: 단일 전송과 호스트 인증 관리

1차 구현은 직접 SIWC OAuth PKCE 및 Responses SSE를 사용해야 한다(SHALL). 호스트는 서명/issuer/audience/nonce/만료를 검증한 뒤 자격 증명을 0600 파일에 저장하고 회전 갱신을 직렬화해야 한다(MUST). 인증 관리 동작은 호스트 루프백에서 사용자가 명시적으로 시작해야 한다(MUST).

#### Scenario: 로그인과 로그아웃

- **WHEN** 사용자가 호스트 Reader에서 Continue with ChatGPT를 누른다
- **THEN** 별도 127.0.0.1 콜백 리스너와 새 state/nonce/PKCE가 시작되고 시스템 브라우저가 열린다
- **AND** 다른 계정/클라이언트의 자격 증명을 덮어쓰지 않고 검증된 등록만 활성화한다
- **AND** 로그아웃은 원격 refresh-token 폐기를 시도하고 미확인 시 이를 표시하며 로컬 토큰 사용을 중단한다

#### Scenario: 원격 문서 뷰의 인증 관리 거부

- **WHEN** 호스트 루프백 이외의 Reader origin이 로그인이나 로그아웃을 요청한다
- **THEN** 호스트는 동작을 거부하고 Mac에서 로그인하도록 표시한다
- **AND** 문서 대화 요청의 기존 origin 및 승인 문서/서비스/리비전 검증을 유지한다

### Requirement: Immutable question context and safe reselection

The host MUST retain each user question's original verified selection/context/revision independently of the current composer selection. Reopening a different subpassage in the same paragraph SHALL reuse the conversation and update the current blockquote. Provider history MUST associate each prior question with its original context and the current question with its newest accepted context.

#### Scenario: Two selections in the same paragraph

- **WHEN** a completed question about one subpassage is followed by Ask on another subpassage of that paragraph
- **THEN** the same conversation opens with the newest selected quote
- **AND** the first question retains its original selection while the new question captures the new selection

#### Scenario: Reselection during streaming

- **WHEN** a different subpassage is selected while a response is streaming
- **THEN** changing that conversation's composer context is rejected until completion or explicit interruption
- **AND** the active run's frozen question context is preserved

#### Scenario: Lost send acknowledgment

- **WHEN** the host accepts a question but its HTTP acknowledgment is lost
- **THEN** the view recovers the original message identity from authoritative local history
- **AND** a completed question is not resent or duplicated, even if the original request has an older view version

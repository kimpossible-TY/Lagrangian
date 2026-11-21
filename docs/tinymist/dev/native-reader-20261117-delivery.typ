#set page(paper: "a4", flipped: true, margin: 14mm)
#set text(font: "Apple SD Gothic Neo", size: 9pt, lang: "ko")
#set par(leading: 0.6em)
#set table(inset: 5pt, align: left)

= NR04 — native app·engine·Reader 전달 설계

대상: `kimpossible-TY/Lagrangian`, baseline `5d71618e7ee320edbe759511fe634024fc8104a6`.
계약: `lagrangian-native-reader-20261117-plan-v1:NR04:a90defb86142`.
아래 경로·행은 모두 이 SHA의 `git show SHA:path` 기준이다. 선행 `MIGRATION.md`와
`source-evidence.json`의 F18을 실제 blob과 대조한 정적 조사이며, 제안은 구현 완료를 뜻하지 않는다.
현재 Mac 상태·설치본·live activation·GUI·성능·CI 성공은 확인하거나 추정하지 않았다.
`scripts/mac` 작업 트리 및 사용자의 dirty 변경은 읽거나 반영하지 않았다. 통합 때 baseline 이후 drift를 재평가해야 한다.

== 1. 확인된 전달 경계

#table(columns: (0.35fr, 2.3fr, 3.35fr),
  [근거], [baseline 경로·행], [확인된 사실],
  [E1], [`.github/workflows/flow-engine.yml:16–41,64–90,129–142,169–203`],
  [main push와 수동 dispatch, docs/OpenSpec/Markdown 제외, 같은 ref의 이전 run 취소. Reader는 hit/miss 모두 현재 SHA로 생성·게시. app build와 stage는 miss에서만 실행.],
  [E2], [`scripts/engine-input-hash.py:20–41,63–91,103–128`],
  [Swift·sources.json·branding·guide·HTML Reader tree는 engine 입력이 아니다. Rust/Cargo/vendor와 paged frontend·typst-dom·reader-common의 비테스트 소스는 포함. OS/arch도 포함.],
  [E3], [`scripts/reuse-engine-artifact.py:36–52,65–90,135–145,154–185`],
  [보존된 hash marker와 engine artifact로 hit 선택. payload에 Lagrangian.app 디렉터리를 요구하고 전체를 재배열 없이 재게시. 검증은 unsigned engine checksum·target/profile이며 앱의 현재 SHA를 요구하지 않는다.],
  [E4], [`scripts/flow-app.py:39–44,140–169,172–222`],
  [sources.json으로 Swift 컴파일. branding icon·Info.plist·LICENSE·guide PDF 생성, engine 복사·서명 후 앱 서명·검증. 외부 engine은 version과 follow-system-theme probe를 거친다.],
  [E5], [`scripts/flow-app.py:258–286,329–403`],
  [stage는 unsigned engine·checksum·release.json·앱을 묶으며 Cargo metadata/target 출력에 의존. fetch는 선택 run의 engine 무결성과 build target/profile을 검증하고 경로를 출력한다.],
  [E6], [`scripts/reader_bundle.py:100–164,240–293,304–340,389–428,451–478,626–654`],
  [index의 blob/mode로 bundle 생성, headSha·bundleChecksum·archiveSHA256·각 파일/mode/symlink 검증. run headSha와 비교한 뒤 staging을 교체. fetch는 설치하지 않는다.],
  [E7], [`tools/flow-reader/install.py:25–45,125–154`],
  [staged bundle을 복사 전후 재검증하고 headSha를 release revision으로 사용. 기존 immutable release의 변경을 거부한다.],
  [E8], [`scripts/mac/auto-update-engine.sh:22–28,57–61,98–105,117–155,164–200`],
  [고정 run의 SHA detached checkout에서 engine/Reader에 같은 run-id 전달, build --engine으로 앱 재패키징. app/Reader revision 및 readiness 확인 뒤 마지막 marker 기록. 실패 trap은 보고·종료한다.],
  [E9], [`scripts/flow-app.py:459–520`; `scripts/mac/test-auto-update-engine.sh:38–66`],
  [app 교체 중 실패는 이전 bundle·실행 profile 복구를 시도. updater fixture는 watch 후 재선택·취소된 최신 run 뒤 성공한 선행 run 선택·과거 run 역행 방지를 다룬다. 전체 app+Reader rollback 증거는 아니다.],
)

*현재 위험:* Swift-only push는 workflow를 시작하지만 engine hash를 바꾸지 않는다(E1/E2).
hit이면 app compile/stage를 건너뛰고 구 app·구 release.json까지 올린다(E3).
이를 새 run의 완성된 최신 앱으로 배포하는 소비자는 Swift/resource 변경을 잃는다.
다만 baseline updater는 새 SHA에서 재패키징하므로(E8), 구 앱이 현재 Mac에 설치됐다는 결론은 낼 수 없다.
HTML-only는 새 Reader bundle을 얻지만 engine/app은 과거 bytes일 수 있다. reader-common 변경은 engine miss가 될 수 있으므로 이 둘을 일반화하지 않는다.

== 2. 보존 계약과 두 가지 최소 수정 대안

보존: `apps/macos/sources.json:1–20`을 packaging/tests의 유일 Swift 목록으로 유지한다.
`apps/macos/AGENTS.md:9–17`의 소유권·validate-before-stop와 E4/E7/E9의 서명·외부 engine·검증·복구 경계를 재사용한다.
native 본문/interaction은 앱 책임으로 추가하되 engine 전체 재작성이나 기존 web/terminal 소비자 제거를 전제하지 않는다.
accepted `openspec/specs/reader-bundle/spec.md:8–30,42–68` 및
`openspec/specs/flow-macos-app/spec.md:93–118,142–192,223–252`가 현재 전달 계약이다.
활성 `openspec/changes/rename-product-lagrangian/design.md:3–8`의 제품명 변경과 Rust/protocol/환경변수 식별자 보존을 따른다.

#table(columns: (0.5fr, 2.45fr, 2.8fr),
  [대안], [최소 변경 경계·효과], [차이·위험·spec 처리],
  [A / 추천],
  [기존 engine artifact 재사용은 그대로 두고, hit/miss 뒤 현재 checkout에서 build --engine으로 native app을 생성하는 별도 게시 단계를 둔다. miss는 이미 생성한 앱을 이용 가능. 최신 앱용 sibling artifact와 같은 run의 전달 manifest를 추가하고 소비자가 이를 선택하게 한다.],
  [engine artifact의 이름/layout/unchanged 재게시 계약과 provenance를 보존. 기존 payload 안 앱은 과거 build 부속물로 남으므로 최신 앱 선택에 사용 금지. 앱 fetch 검증과 updater 소비 전환이 필요. 새 artifact 이름·schema는 PM 결정 및 OpenSpec delta 대상.],
  [B],
  [기존 artifact 안 Lagrangian.app만 현재 checkout으로 다시 만들고 stage를 hit/miss 공통화한다. engine unsigned bytes·checksum은 재사용하고 app metadata와 engine provenance를 별도로 기록한다.],
  [artifact 하나를 유지하지만 unchanged 재게시 계약을 깨므로 두 accepted spec의 delta가 필요. E5 stage의 Cargo metadata 의존을 제거/주입해야 hit에서 Rust 없이 동작. 구 release.json과 새 앱을 섞지 않도록 기존 fetch/소비자 모두 이행 검증 필요.],
)

A는 기존 fetch-engine 계약을 유지하면서 최신 native app 전달만 명시적으로 추가하는 안이다.
후속 구현 범위는 workflow·packager/manifest·검증된 app fetch·updater 연동·fixture로 제한한다.
이 문서에서는 이를 수정하지 않는다. engine hash에 모든 Swift/resource를 넣어 매번 Rust를 빌드하는 방식은 책임과 비용을 다시 결합하므로 추천하지 않는다.
E4의 external build는 engineBuild를 자동 상속하지 않고 engineSource=external로 기록한다.
현재 build manifest만 복사해 원 engine provenance가 보존됐다고 주장할 수 없다.

== 3. revision·resource·compatibility 계약 제안

#table(columns: (1fr, 3.4fr),
  [기록 단위], [요구하는 의미·검증],
  [전달 run], [한 번 확정한 repository/workflow/run-id/run headSha와 성공 상태. app·engine·Reader의 artifact ID/checksum을 묶는 전달 manifest를 제안한다. 각각 --branch 최신 조회를 반복하지 않는다. run-id 동일성과 engine source SHA 동일성은 별개다.],
  [App], [app source SHA=run headSha, clean source, sources.json 및 실제 입력 digest, app executable·resource 결과 checksum, signing identity/certificate를 기록. CI app 검증과 Mac 재서명 결과를 구분한다. 기존 sourceRevision/sourceDirty 의미를 보존한다(E4).],
  [Engine], [원 빌드 run/source SHA·engine input-set hash·unsigned binary SHA·version·target/profile/flags와 앱에 서명된 binary SHA를 분리. E4의 engineInputSHA256은 입력 집합 hash가 아니라 서명 전 binary hash다. cache hit에서 원 provenance를 현재 app SHA로 덮지 않는다.],
  [Reader], [headSha=선택 run headSha, bundleChecksum·archiveSHA256·파일/mode/symlink·설치 release revision을 별도 보존. engine source SHA가 더 오래되어도 허용하되 compatibility 검증을 통과해야 한다(E6/E7).],
  [Protocol], [현재 CLI probe를 유지하고 native renderer/IPC·source-history 등 실제 사용할 capability/schema 요구와 제공값의 호환 판정을 별도 기록. 같은 run·checksum 일치는 프로토콜 호환 증명이 아니다. 지원 버전/handshake는 미결정이며 불일치는 activation 전 거부해야 한다.],
)

*Native resource manifest 제안:* packaging owner가 입력과 bundle 목적지의 명시 allow-list를 단일 소유한다.
현재 E4의 branding PNG→icns, Info.plist 생성 입력, LICENSE, guide typ와 실제 include/image 의존 및 생성 PDF,
후속 native renderer용 font/shader/data가 생기면 그 입력·toolchain과 결과 경로/hash를 기록한다.
Swift 목록은 sources.json을 재사용하고 별도 중복 목록을 만들지 않는다. 임의 디렉터리 복사나 HTML bundle로 native resource 전달을 대신하지 않는다.
guide-only 변경은 현재 docs paths-ignore로 workflow 자체가 시작되지 않는다(E1). native release resource와 그 의존 변경의 trigger 예외를 정하고,
일반 docs-only 제외는 보존해야 한다. generated resource를 바꾼 것만으로 source가 전달됐다고 판단하지 않는다.
서명은 configured identity 부재 시 실패하는 기존 정책과 engine/app 인증서 일치 검증을 보존한다(`scripts/flow-app.py:76–89,121–138`).

== 4. 후속 검증표 — 요구사항이며 이번에는 실행하지 않음

공통 fixture: A=baseline payload(run R0, engine E0, app A0), B=단일 입력을 바꾼 가상 revision R1.
격리 temp checkout·fake HOME·주입한 gh/command runner로 먼저 검사한다. 실제 Swift packaging/서명은 별도 macOS 검증,
Rust miss는 승인된 원격 빌드, main 자동 CD와 live readiness/GUI는 이후 별도 gate다.
각 행은 실제 revision·명령·exit code·assertion·skip 사유를 남기며 fixture 통과를 native 실행 성공으로 보고하지 않는다.

#table(columns: (1.15fr, 2.7fr, 2.1fr),
  [사례], [fixture/negative case], [추천 A의 수용 조건·담당],
  [Swift-only / hit], [R1에서 sources.json에 든 Swift 동작 marker만 변경. E0 artifact와 hash marker를 fake gh로 반환. 먼저 baseline이 A0를 재게시함을 assertion으로 재현(E2/E3).], [engine hash/bytes 불변·Cargo 호출 0·새 앱 marker와 app SHA=R1·Reader SHA=R1. delivery owner.],
  [Native resource-only / hit], [branding 및 새 manifest의 resource를 각각 변경. 누락/추가 목적지·변조 결과도 주입.], [engine 재사용·새 resource bytes/checksum·서명 검증, allow-list 누락은 실패. guide/include-only trigger도 검사. packaging owner.],
  [HTML-only / hit], [tools/flow-reader/web 파일만 변경하고 E0 반환.], [engine 불변, Reader SHA=R1 및 checksum 변경, 최신 app source SHA=R1. reader bundle/delivery owner.],
  [Engine-only / miss], [Rust 입력 변경, 일치 marker 없음.], [새 engine provenance/hash·현재 app·현재 Reader를 한 run으로 결합. Cargo는 miss 분기만. 원격 build/delivery owner.],
  [Hit/miss 대칭], [동일 R1을 보존 artifact 있음/없음으로 각각 실행. expired·missing marker도 miss로 처리.], [두 경로 모두 현재 app/resources/Reader 산출·검증. miss만 Rust/asset 준비. engine bytes 같음을 모든 miss에 강제하지 않음. delivery owner.],
  [Shared input], [reader-common 비테스트 파일 변경.], [engine input hash 변경과 새 Reader bundle을 함께 확인. HTML-only와 구별. engine/Reader owner.],
  [혼합 revision·변조], [app=R0/Reader=R1, 서로 다른 run, 잘못된 bundle headSha/checksum/archive/file/mode/symlink, engine hash 불일치.], [전체 preflight 실패·activation 0·기존 app/Reader와 marker 유지. 오래된 engine 원 SHA만으로는 실패시키지 않음. delivery owner.],
  [Compatibility·서명 실패], [preview capability 누락·native schema 불일치·target/profile 오류·configured certificate 없음/다름.], [호환성/서명 오류를 구분하여 activation 전 실패, ad-hoc 자동 대체 금지. packaging/native protocol owner.],
  [취소·부분 게시·실패], [R1 취소 후 성공 R0, watch 중 R2 출현, app packaging 실패 또는 sibling artifact 누락.], [성공하고 완전한 run만 선택·watch 뒤 재조회. 취소/불완전 run 설치 금지, 실패 marker 미전진. delivery owner.],
  [교체 실패·rollback], [앱 교체 후 health 실패, 앱 성공 뒤 Reader refresh 실패, rollback 중 재실패를 각각 주입.], [이전 app+engine+Reader tuple·설정/데이터 복구 및 실패 명시. 전체 복구 불가 시 불확실 상태와 재시도 정책을 기록하고 성공 marker 금지. lifecycle/delivery owner.],
  [설치 layout·재서명], [staging 밖 상대 import, shared symlink, native resource 경로 및 Mac signing identity를 격리 검증.], [복사 전후 Reader 검증·app/resource/engine 검증, 이전 release 불변. 실제 service/GUI gate는 별도 승인·증거 필요. packaging/reader owner.],
)

재사용할 fixture 위치: `tests/flow-app/test_engine_artifact_cache.py:31–96,115–162`는 hash·hit 선택·engine 검증,
`tests/flow-app/test_reader_bundle.py:89–177,202–356`는 bundle·복사·fetch negative case,
`scripts/mac/test-auto-update-engine.sh:38–66`는 watcher 선택 정책의 출발점이다. 이번 조사에서는 실행하지 않았다.

== 5. 미결정·통합 gate

- 추천 A의 artifact/schema 이름, native resource manifest 위치와 trigger 의존 폐쇄, native protocol/capability 버전은 PM·통합 owner가 확정해야 한다.
- 현재 E9는 앱 내부 실패 복구이고 E8은 Reader 실패 시 marker만 보류한다. end-to-end 자동 rollback은 미구현으로 취급하며 app/Reader tuple 복구·영속 데이터 하위 호환·실패 중단 정책을 설계해야 한다. watcher의 과거 run 자동 역행 방지와 명시 rollback을 구별한다.
- baseline 이후 updater drift는 후속 통합에서 소유자의 변경과 대조한다. 이 문서는 사용자 dirty 내용을 읽거나 덮어쓸 권한을 부여하지 않는다.
- 검증 범위는 baseline 정적 대조와 본 Typst 문서 최소 구문 확인뿐이다(설치된 Typst 0.15.1 사용). 이 파일은 link-docs.mjs 생성 대상이 아니므로 Markdown 재생성은 해당하지 않는다. 소스 구현·packaging·서비스 설치/재시작·Rust·network·수동 CI/Cloud·GUI/성능 실행은 수행하지 않는다.

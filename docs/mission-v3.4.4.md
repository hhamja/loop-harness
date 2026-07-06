# 임무: Loop Harness — 범용 루프 엔지니어링 Claude Code 플러그인 구축 (v3.4.4 최종)

[English](mission-v3.4.4.en.md) | [**한국어**](mission-v3.4.4.md)

아래 전체를 복사해서 Claude Code에 붙여넣으세요.

**v3.4.3 → v3.4.4 변경 요지:** 실증 검토 반영 3건 (Claude Code v2.1.201 실측 기준) — ① 도그푸딩 permission mode 정정: headless(`-p`)에서는 권한 프롬프트를 띄울 수 없어 `acceptEdits`로는 **모든 Bash 도구 호출이 거부됨**(실측 — 루프의 test 실행·verifier 채점·스모크 체크 전부 불가. 스모크 ②는 권한 계층 거부가 guard deny로 오판되는 위양성까지 발생) → `--permission-mode bypassPermissions`로 교체(일회용 도그푸딩 프로젝트 한정). hook의 deny는 permission mode와 독립적으로 발화함이 실측 확인되어 스모크 ②의 판정 전제는 유지 ② verifier_guard 폴백 트리거 확장 — "`agent_type` 필드 부재"만 정의돼 있던 것을 "필드는 존재하나 값 불일치(deny 미발화가 디버그 로그로 실증, 매칭 문자열 조정 1회 재시도 후)"까지 포함: 값 불일치 환경에서 수용 기준(실차단/필드 부재 폴백)의 어느 분기도 성립하지 않아 교착하던 경로 제거. 수용 기준·스모크 ②·README 한계 문구 동기화 ③ `--verify-only` read-only 보장 문구를 "잔존 marker 없는 신선한 세션 기준"으로 한정 — 동일 세션에 marker가 잔존하면 verify-only 턴 종료도 판정 4에 도달해 `.last-usage`가 갱신되므로 "state.md 1줄이 유일한 예외" 문구가 자기모순이었음(메커니즘 불변 — 보장 대상을 지속 파일(커밋 대상)로 정의하고 숨김 임시 파일은 범위 밖으로 명시). 설계 구조 변경 없음(신규 파일·hook 이벤트 추가 없음).

**v3.4.2 → v3.4.3 변경 요지:** session_id 획득 메커니즘 명세 — 침묵 실패 경로 제거. ① `.run-marker`에 기록할 session_id의 획득 경로가 미명세였음(값이 틀리거나 없으면 판정 3이 항상 통과되어 Stop gate 전체가 조용히 무력화) → Bash 환경변수 `CLAUDE_CODE_SESSION_ID`로 명시. 공식 문서에 기재되지 않은 변수라 버전 의존으로 취급하며(v2.1.201에서 실재 확인) 스모크 체크 ③으로 실증, 미설정 시 `unknown` 기록 ② 판정 3에 `unknown`/파싱 불가 → 통과(fail-open) 분기 추가, env 미제공 환경의 gate 상시 비활성을 알려진 한계 3으로 명시(미차단 방향 — 이 환경에서는 `.last-usage`도 미기록이며, 수용 기준의 토큰 항목·Stop hook 가드 항목은 README 한계 명시로 대체 충족) ③ 스모크 체크 ③ 신설 — env var 존재 확인 + `.run-marker`의 session_id와 stop hook 입력 session_id의 일치 대조(중첩 headless 세션의 부모 env 상속 오염 방어) ④ 구현 함정 힌트 2건 추가 — 판정 4 mtime 조회의 stat 포터빌리티(macOS/Linux 분기 또는 `[ -ot ]` 파일 비교), hook 스크립트 디버그 관측성(`LOOP_GUARD_DEBUG=1` 시 수신 입력 JSON 로그 — 스모크 체크 ② '필드 부재' 실증·③ 일치 대조의 수단, 기본 비활성) ⑤ `.last-usage` 주석에 동일 세션 후속 비루프 턴의 delta 혼입 가능성 명시. 설계 구조 변경 없음(신규 파일·hook 이벤트 추가 없음).

**v3.4.1 → v3.4.2 변경 요지:** 문서 정합성 수정 — ① hooks 명세의 "Stop 이벤트만 사용" 문구를 루프 게이트 판정으로 범위 한정: verifier_guard.sh의 PreToolUse(Bash) 등록(verifier 명세·수용 기준이 요구)과의 문면상 모순 해소 ② 산출물 구조에 `.claude-plugin/marketplace.json` 추가 — README 설치 경로 ①(marketplace 경유)이 이 저장소 단독으로 작동하도록 README 요건·수용 기준 동기화 ③ `.last-usage` 기록 조건의 "판정 3까지 통과" 중의 표현을 "판정 4 도달(동일 세션 marker 존재)"로 명확화 ④ `disallowedTools`의 서브에이전트 frontmatter 지원도 버전 의존일 수 있음을 명시(미지원 시 무시될 뿐 무해 — 1차 방어는 tools 허용목록에 Write/Edit 부재). 설계 구조 변경 없음.

**v3.4 → v3.4.1 변경 요지:** 엣지케이스 명세 보완 — ① Stop gate 판정 4에 state.md 파일 부재 시 통과(fail-open) 명시 ② 같은 세션의 잔존 marker에 `--verify-only` 턴이 차단될 때 state.md 1줄 기록이 read-only 보장의 유일한 예외임을 알려진 한계 2·README·수용 기준에 명시(무수정 검증은 신선한 세션 기준) ③ state.md "append 금지"의 적용 범위를 사이클 갱신으로 한정(차단 해소용 1줄 append는 예외) ④ loop-init 감지 예시를 비-JS 생태계(pyproject.toml, Makefile, Cargo.toml 등)로 확장. 설계 구조 변경 없음.

**v3.3 → v3.4 변경 요지:** ① verifier 명세의 낡은 사실 단정 2건 정정 — "서브에이전트 frontmatter hooks/permissionMode 미지원" 단정을 "버전 의존·플러그인 배포 에이전트에서는 미확정, 미지원 가정"으로 완화; "플러그인은 permissions deny 배포 불가"를 "settings.json 배포 가능 버전이 있으나 세션 전역 적용이라 verifier 단독 스코프 불가"로 정정. 설계 결론(플러그인 레벨 PreToolUse hook이 기본 수단)은 불변 ② Stop gate 판정 4의 오차단 시나리오 대응 — 차단 reason에 "루프 무관 턴이면 state.md에 'loop interrupted' 1줄만 기록 후 종료" 분기 지시를 추가하고, "state.md 미갱신 상태로 중단된 loop-run 세션에서는 다음 턴 종료가 1회 차단될 수 있음(1회 기록 후 자연 해소)"을 알려진 한계로 hooks 명세·README에 명시.

**v3.2 → v3.3 변경 요지:** ① `agent_type` 필드 **부재 시 폴백** 정의 — 스모크 체크에서 hook 입력에 `agent_type` 필드 자체가 없음이 확인되면 verifier_guard는 비활성(전체 fail-open)으로 유지하고, 방어를 `disallowedTools` + verifier 프롬프트 내 명시적 금지 지시 2중으로 격하, README 알려진 한계에 1줄 명시. 관련 수용 기준은 "실차단 **또는** 문서화된 격하"로 충족 ② 클린 재실행 기준 완화 — "플러그인 코드 수정 0회"를 "플러그인 **로직** 수정 0회(문서·주석·README 수정 제외)"로 정의하고, 외부 요인 실패(네트워크, 패키지 레지스트리, 스캐폴딩 도구 버전 등)는 실패 횟수에 계상하지 않고 해당 단계만 재시도.

**v3.1 → v3.2 변경 요지:** ① `--verify-only`는 `.run-marker`를 기록하지 않음 — 전 과정 read-only 보장(marker를 쓰면 Stop gate 판정 4가 verify-only 자신을 차단하는 데드락) ② 토큰 추정 단위를 "사이클별" → "run별"로 정정 — Stop hook은 loop-run 1회 호출(1턴)당 1번만 발화하므로 사이클 단위 측정은 구조적으로 불가 ③ verifier_guard 리다이렉트 차단에 허용 예외(`2>&1`, `>/dev/null` 등) 명시 — 테스트 명령 관용구 오탐 방지 ④ `agent_type` 판정을 부분 일치("verifier" 포함) + 필드 부재 시 fail-open으로 정의, verifier 실차단 positive test를 도그푸딩·수용 기준에 추가 ⑤ 비대화형(headless) 규칙 명시 — loop-init은 질문 대신 자동 감지, 실패 시 TODO placeholder 기록 후 진행; 에스컬레이션의 headless 기대 동작 = 옵션 출력 + 사유 기록 + 종료 ⑥ 도그푸딩에 verifier 도구 가용성 스모크 체크 추가(플러그인 에이전트 tools 목록 첫/마지막 항목 드롭 이슈 보고 방어) ⑦ `.last-usage` 기록을 "동일 세션 marker 존재 시"로 스코프 + `.run-marker` 잔존이 의도된 동작임을 주석으로 명시.

## 전역 규칙

- 언어: 플러그인 파일(SKILL.md, 커맨드, 에이전트 정의, README, 스크립트)은 전부 영어로 작성한다(토큰 효율·이식성). 단어 예산은 영어 단어 기준, `wc -w`로 계산. 채팅 보고와 최종 사용법 요약은 한국어.
- 생성 위치: 현재 작업 디렉터리의 `loop-harness/`
- 버전 관리: plugin.json에 version 필드, 루트에 CHANGELOG.md — 기존 프로젝트 재배포 대비.
- 커맨드 표기: 플러그인 커맨드는 항상 `/loop-harness:<name>`으로 네임스페이스되어 노출된다. 본문의 `/loop-init` 등은 축약 표기이며, 사용자 노출 문서(README, quickstart)에는 반드시 전체 형태(`/loop-harness:loop-init`)를 쓸 것.
- 경로 규칙: hooks.json에서 스크립트를 참조할 때 반드시 `${CLAUDE_PLUGIN_ROOT}` 기준 경로를 쓸 것 — 상대 경로는 글로벌 설치 시 깨진다(플러그인은 설치 시 캐시 디렉터리로 복사됨).

## 배경 (참고 개념 요약 — 링크 fetch 불필요)

루프 엔지니어링: 에이전트에 매 턴 직접 프롬프트하는 대신, "에이전트를 프롬프트하는 시스템"을 설계하는 방식.

- 루프 = 검증 가능한 정지 조건(goal/rubric)이 충족될 때까지 실행 → 피드백 수집 → 자가 수정을 반복하는 재귀 구조
- 6대 구성 요소: Automations(커맨드/hooks), Worktrees(병렬 격리), Skills(프로젝트 지식 외부화), Plugins(배포 단위), Sub-agents(maker/checker 분리), Memory(디스크 기반 상태)
- 핵심 원칙 3가지:
  1. 코드를 쓴 에이전트가 자기 숙제를 채점하면 안 됨 → 독립 컨텍스트의 verifier sub-agent가 채점
  2. "done"은 주장이지 증명이 아님 → 정지 조건은 기계적으로 체크 가능해야 함(테스트 통과, lint clean, 파일 존재 등)
  3. 모델은 실행 사이에 모든 것을 잊음 → 메모리는 컨텍스트가 아니라 디스크에
- 메모리 5단계 프로토콜: fail(실패 기록) → investigate(원인 파악) → verify(검증된 사실화) → distill(일반 규칙화) → consult(다음 실행에서 규칙 참조). 5단계까지 완주해야 세션 간 복리 효과 발생.
- 경계 원칙 3가지 (README에 필수 포함): ① "done"은 증명이 아니라 주장 — 최종 검증은 사람 몫 ② comprehension debt — 루프 산출물에 사람용 리뷰 요약을 강제할 것 ③ 루프·verifier·subagent는 토큰을 소모 — 항상 비용 대비 판단

## 목표

어떤 신규 프로젝트(MVP)에도 "플러그인 설치 1회(머신당) + `/loop-harness:loop-init` 1회(프로젝트당)"로 이식되는 Claude Code 플러그인 `loop-harness`를 구축한다.

설계 불변식: 플러그인 = 불변 로직(글로벌 설치), `.claude/loop/` = 가변 상태(프로젝트 로컬, loop-init이 생성)

## 산출물 구조

```
loop-harness/
├── .claude-plugin/
│   ├── plugin.json                     # 매니페스트(version 필수). 이 디렉토리에는 매니페스트류만 둠
│   └── marketplace.json                # 자체 marketplace 매니페스트 — 설치 경로 ①(marketplace add)용
├── CHANGELOG.md
├── README.md                           # 아래 "README 요건" 참조
├── commands/                           # 이하 전부 플러그인 루트 기준
│   ├── loop-init.md                    # .claude/loop/ 스캐폴드 생성 + 스택 자동 감지.
│   │                                   #   대화형: 감지 실패 시 사용자에게 질문
│   │                                   #   비대화형(-p): 질문 금지 — package.json scripts, pyproject.toml,
│   │                                   #   Makefile, Cargo.toml 등 생태계별 매니페스트에서 감지,
│   │                                   #   실패 시 loop.config.md에 "TODO:" placeholder 기록 + 경고 후 진행
│   ├── loop-run.md                     # 아래 "루프 실행 모델" 참조
│   └── loop-status.md                  # state.md 요약 출력
├── agents/
│   ├── verifier.md                     # 채점 전담 (아래 "verifier 명세" 참조)
│   └── explorer.md                     # 코드베이스 탐색 전담(선택), read-only. frontmatter에 model: haiku
│                                       #   지정으로 저비용 실현. 투입 기준은 SKILL.md에 명시
├── skills/loop-engineering/
│   ├── SKILL.md                        # YAML frontmatter(name, description) 필수.
│   │                                   # 본문 500단어 이하: 개요 + 언제 references를 읽을지 라우팅만
│   └── references/
│       ├── memory-protocol.md          # 5단계 프로토콜 상세 + 기록 템플릿 + [plugin]/[project] 태그 규칙
│       ├── rubric-guide.md             # 검증 가능한 기준 작성법, 좋은/나쁜 예 3쌍 이상,
│       │                               # 비코드 산출물(문서 등)의 기계 검증 예 1개 포함
│       └── worktree-guide.md           # 병렬 실행 절차 + 병합 정책 — 참조 전용. MVP에는 이를 쓰는 명령 없음
├── hooks/hooks.json                    # 자동 인식됨(plugin.json 참조 불필요). 아래 "hooks 명세" 참조
└── scripts/
    ├── check_budget.sh                 # 아래 "토큰 예산" 참조
    ├── stop_gate.sh                    # Stop hook 판정 + run 토큰 추정 기록 (아래 "hooks 명세")
    └── verifier_guard.sh               # PreToolUse(Bash): verifier의 쓰기성 명령 차단 (아래 "verifier 명세")
```

worktree-guide.md의 병합 정책: 병렬 에이전트는 메인 state.md에 직접 쓰지 않는다. 각자 `.claude/loop/results/<task>.md`에 기록하고, 병합은 오케스트레이터만 수행한다.

loop-init이 생성하는 프로젝트 로컬 파일:

```
.claude/loop/
├── goal.md          # 정지 조건 (기계적 체크 가능한 형태로만)
├── rubric.md        # 채점 기준 5~15개, 각 기준에 [ ]/[x] + 검증 명령어 명시
├── state.md         # 시도한 것 / 통과한 것 / 미해결 / run별 토큰 추정치 + 루프 활성 플래그
│                    #   — 매 사이클 "요약 갱신" (사이클 갱신은 append 금지, 100줄 상한.
│                    #     예외: Stop gate 차단 해소용 'loop interrupted' 1줄 append)
│                    #   활성 플래그는 사람·loop-status용 정보. hook 차단 판정은 .run-marker 기준(hooks 명세)
├── memory.md        # 5단계 프로토콜 기록. distill된 규칙 상단 유지, raw fail 로그 200줄 초과 시 압축
├── review.md        # 최신 사이클의 사람용 리뷰 요약(변경 파일, 핵심 변경 요지, 리스크) — 매 사이클 덮어씀
├── loop.config.md   # test/lint/build 명령 + max_iterations(기본 10) + 에스컬레이션 정책
│                    #   — 유일한 스택 종속 지점
├── .run-marker      # loop-run 시작 시 기록: session_id + timestamp. 단, --verify-only는 기록하지 않음.
│                    #   session_id는 $CLAUDE_CODE_SESSION_ID에서 획득("루프 실행 모델" 참조)
│                    #   정상 종료 후에도 삭제하지 않음(의도된 동작 — hooks 명세 참조). 임시 파일, 커밋 금지
└── .last-usage      # stop_gate.sh가 기록하는 run 토큰 추정치(누적 transcript 크기 + 직전 대비 delta).
                     #   동일 세션의 후속 비루프 턴도 판정 4에 도달하므로 delta에 비루프 턴 사용량이
                     #   섞일 수 있음(추정치 한계로 수용). 임시 파일, 커밋 금지
```

- loop-init은 `.claude/loop/.*`(숨김 임시 파일)을 .gitignore에 추가한다. 나머지 파일은 커밋 권장(팀 공유·세션 복원)이 기본값이며, README에 이 정책을 명시한다.

## verifier 명세

- 별도 sub-agent, 독립 컨텍스트. rubric.md만 기준으로 채점.
- frontmatter: `tools: Read, Grep, Glob, Bash` + `disallowedTools: Write, Edit` (이중 방어).
- 알려진 이슈 방어: 플러그인 에이전트에서 frontmatter tools 목록의 첫/마지막 항목이 스폰 시 드롭된다는 보고가 있다. 작업 순서 3의 스모크 체크로 실증하고, 재현 시 목록 순서 조정 등으로 완화한 뒤 memory.md에 `[plugin]` 태그로 기록한다.
- 주의: tools 필드는 bare 도구명만 허용된다(`Bash(npm test:*)` 같은 지정자 불가). "read-only Bash" 옵션도 존재하지 않는다. `disallowedTools`의 서브에이전트 frontmatter 지원 여부 역시 버전 의존일 수 있다 — 미지원이면 무시될 뿐 무해하며, 1차 방어는 tools 허용목록에 Write/Edit가 애초에 없다는 점이다. 서브에이전트 frontmatter의 hooks/permissionMode 지원 여부는 버전 의존이며, 특히 플러그인 배포 에이전트에서의 동작은 미확정이다 — 본 설계는 미지원을 가정한다. 일부 버전은 플러그인의 settings.json 배포를 지원하나 permissions 규칙은 세션 전역에 적용되어 verifier에게만 스코프할 수 없다 → 쓰기 성향 Bash의 verifier 한정 차단은 플러그인 레벨 PreToolUse hook(verifier_guard.sh)을 기본 수단으로 한다.
- verifier_guard.sh (PreToolUse, matcher: Bash):
  - 스코프 판정: hook 입력의 `agent_type`에 "verifier"가 **포함**될 때만 검사한다(네임스페이스 접두 등 값 형태 변화 대비 부분 일치). `agent_type` 필드가 없거나 매칭되지 않으면 무조건 통과(fail-open) — 메인 에이전트·다른 에이전트의 Bash는 절대 차단하지 않는다.
  - **폴백(필수):** 작업 순서 3의 스모크 체크에서 ⓐ hook 입력에 `agent_type` 필드 자체가 존재하지 않음이 확인되거나, ⓑ 필드는 존재하나 verifier 스폰 시에도 값에 "verifier"가 포함되지 않아 deny가 발화하지 않음이 `LOOP_GUARD_DEBUG` 로그로 실증되면(이 경우 로그의 실제 값 형태로 매칭 문자열 조정을 1회 시도하고, 그래도 미발화일 때), 이 환경에서는 스코프 판정이 불가능한 것이다 → ① guard는 비활성(전체 fail-open) 상태로 유지 ② 방어를 `disallowedTools: Write, Edit` + verifier 프롬프트 내 명시적 금지 지시(쓰기성 Bash 명령 금지 목록을 verifier.md 본문에 기재)로 격하 ③ README "알려진 한계"에 1줄 명시 ④ memory.md에 `[plugin]` 태그로 기록. 이 경우 수용 기준의 verifier 차단 항목은 "문서화된 격하"로 충족된다.
  - 차단 패턴: rm, mv, cp, sed -i, tee, 파일 경로로의 `>`/`>>` 리다이렉트, chmod, git commit/push/checkout/reset, npm publish 등.
  - 허용 예외(오탐 방지 필수): `2>&1`, `>/dev/null`, `2>/dev/null`, `&>/dev/null` — 이 관용구까지 차단하면 verifier가 테스트 명령 자체를 실행할 수 없다.
  - 차단 시 공식 hooks 스키마의 deny 응답(hookSpecificOutput의 permissionDecision "deny" + 사유)을 반환한다.
  - 디버그 관측성(필수): `LOOP_GUARD_DEBUG=1` 환경변수 설정 시 수신한 hook 입력 JSON을 `.claude/loop/.hook-debug.log`(숨김 임시 파일 — `.claude/loop/.*` gitignore 규칙에 포함)에 append하는 분기를 verifier_guard.sh와 stop_gate.sh 양쪽에 둔다. 기본(미설정) 상태에서는 어떤 기록도 하지 않는다 — `--verify-only` 무수정 보장은 디버그 비활성 기준. 스모크 체크 ②의 "agent_type 필드 부재/값 불일치" 판별과 ③의 session_id 일치 대조는 이 로그로만 가능하다.
  - 불변식은 "완전 읽기 전용"이 아니라 **"소스·루프 상태 파일 비수정"**이다. 테스트/빌드 실행에 따른 부수적 쓰기(캐시, coverage 등)는 허용.
- verifier는 판정 리포트만 반환한다 (기준별 pass/fail + 근거 명령 출력). rubric.md 체크박스와 state.md 갱신은 리포트를 받은 메인 에이전트가 수행한다. verifier는 어떤 파일도 수정하지 않는다.

## 루프 실행 모델 (/loop-harness:loop-run)

- 기본 동작: rubric 전 기준 통과 또는 안전장치 발동까지 사이클 반복.
- 옵션: `--once` = 1사이클만 실행(점진 채택·비용 통제용). `--verify-only` = 구현 없이 verifier 채점 1회만 실행하고 리포트 출력(기존 코드 리뷰 용도, 점진 채택 진입점). **`--verify-only`는 전 과정 read-only: `.run-marker`를 포함해 어떤 파일도 기록·수정하지 않는다**(잔존 marker 없는 신선한 세션 기준 — 동일 세션에 marker가 잔존하면 턴 종료 시 stop_gate가 `.last-usage`를 갱신한다, hooks 명세·알려진 한계 2 참조) — marker를 쓰면 Stop gate 판정 4가 verify-only 자신을 차단한다.
- 1사이클 = 구현 → verifier 채점(phase gate, 사이클 종료 시점 1회만) → 메인 에이전트가 rubric/state/memory/review 갱신.
- loop-run은 시작 시 `.claude/loop/.run-marker`에 session_id + timestamp를 기록한다(`--verify-only` 제외). session_id는 Bash 환경변수 `CLAUDE_CODE_SESSION_ID`에서 획득한다 — 공식 문서에 기재되지 않은 변수라 버전 의존으로 취급하며, 작업 순서 3의 스모크 체크 ③으로 실증한다. 미설정/빈 값이면 `unknown`을 기록한다(hooks 명세 판정 3에서 fail-open).
- 토큰 기록: 에이전트는 자기 토큰 사용량을 직접 알 수 없다. 기록 단위는 **run(=loop-run 1회 호출)** 이다 — Stop hook은 턴 종료 시 1회만 발화하므로 사이클 단위 측정은 구조적으로 불가능하며, 이를 주장하지 말 것. stop_gate.sh가 hook 입력의 transcript 크기(바이트/4)로 추정치를 계산해 `.last-usage`에 누적값과 직전 기록 대비 delta를 기록하고, 메인 에이전트가 다음 갱신 때 state.md에 "추정치"임을 명시하여 반영한다. 정밀 측정을 주장하지 말 것.
- 루프 안전장치 (필수):
  - loop.config.md의 max_iterations 초과 시 루프 중단 + state.md에 중단 사유 기록
  - 동일 기준이 3회 연속 실패하면 루프 중단 + 사용자에게 옵션 2~3개로 에스컬레이션 질문. 비대화형(headless)에서는 응답을 받을 수 없으므로 기대 동작 = 옵션 출력 + state.md에 중단 사유 기록 + 종료.
  - 안전장치 없는 "통과까지 무한 반복" 구현은 금지

## hooks 명세

- 루프 게이트 판정에는 `Stop` 이벤트만 사용한다. SubagentStop은 사용하지 않는다 — verifier는 파일을 수정하지 않으므로 SubagentStop으로 state.md 갱신을 요구하면 데드락이 된다. verifier_guard.sh의 `PreToolUse(Bash)` 등록은 이와 별개이며(verifier 명세 참조), hooks.json에는 두 이벤트가 함께 등록된다.
- stop_gate.sh 판정 순서 (전부 해당해야만 차단):
  1. `.claude/loop/` 없음 → 통과 (루프 무관 세션 보호)
  2. 입력의 `stop_hook_active == true` → 통과 (무한 차단 루프 방지)
  3. `.run-marker` 없음, marker의 session_id ≠ 현재 session_id, 또는 marker의 session_id가 `unknown`·파싱 불가 → 통과 (강제 종료 후 잔존 마커가 새 세션을 차단하지 않도록 보호. session_id를 획득하지 못한 run에서는 gate가 비활성 — fail-open, 알려진 한계 3)
  4. state.md mtime < marker timestamp → 차단: exit 0 + `{"decision":"block","reason":"state.md not updated this run. If this turn was loop work: update state.md (attempted / passed / unresolved). If this turn was unrelated to the loop: append exactly one line 'loop interrupted (previous run did not update state)' to state.md, then finish."}`
     — reason의 분기 지시는 오차단 시나리오(state.md 미갱신으로 중단된 loop-run과 같은 세션에서, 이후 루프와 무관한 턴이 1회 차단됨) 대응이다. 강제 갱신을 노이즈가 아니라 유용한 중단 기록으로 전환하며, state.md가 1회 기록되면 mtime > marker timestamp가 되어 이후 자연 해소된다. state.md 파일 자체가 없으면(부분 초기화·수동 삭제 등) mtime 비교가 불가능하므로 차단하지 않고 통과한다(fail-open — 판정 불가 시 차단하지 않는다는 원칙). 구현 힌트: mtime 조회는 macOS(`stat -f %m`)와 Linux(`stat -c %Y`)의 플래그가 다르므로 uname 분기 처리하거나, marker 파일 자체의 mtime과 비교하는 `[ state.md -ot .run-marker ]` 방식을 써도 동치다(marker는 run 시작 시점에 기록되므로).
- `.last-usage` 기록은 판정 1~3의 통과(조기 종료 허용) 분기에 해당하지 않아 판정 4에 도달한 경우 — 즉 동일 세션 marker가 존재할 때 — 에만 수행한다. 루프 무관 세션과 신선한 세션 `--verify-only`의 무수정 보장(동일 세션에 marker가 잔존하면 `--verify-only` 턴의 종료에도 `.last-usage`는 갱신된다).
- `.run-marker`는 정상 종료 후에도 삭제하지 않는다 — state.md가 한 번이라도 갱신되면 mtime > marker timestamp가 되어 이후 stop은 판정 4를 자연 통과한다. 이 의도를 stop_gate.sh 주석에 명시할 것(잔존 marker를 버그로 오인 방지).
- 차단 응답은 공식 hooks 스키마(JSON decision:block)를 준수한다. 주의: block JSON은 **exit 0에서만 파싱**된다 — exit 2와 병용하면 JSON이 무시된다.
- 알려진 한계 1: `claude --resume` 세션에서 session_id 변화로 판정 3이 gate를 무력화할 수 있다. 오차단이 아닌 미차단 방향의 실패이므로 수용하고, README에 한 줄로 명시한다.
- 알려진 한계 2: state.md 갱신 없이 중단된 loop-run과 같은 세션에서는, 이후 루프와 무관한 턴의 종료가 판정 4에 1회 차단될 수 있다(위 reason 분기 지시로 state.md 1줄 기록 후 자연 해소). 유일한 오차단 방향의 한계이므로 README에 한 줄로 명시한다. 이 턴이 `--verify-only`인 경우 차단 해소를 위한 state.md 1줄 기록이 read-only 보장(지속 파일·커밋 대상 기준)의 유일한 예외가 된다 — 숨김 임시 파일 `.last-usage`는 보장 범위 밖이며 판정 4 도달 시 항상 갱신된다. 수용 기준의 `--verify-only` 무수정 검증은 잔존 marker가 없는 상태(신선한 세션)를 기준으로 수행한다.
- 알려진 한계 3: Bash 환경에 `CLAUDE_CODE_SESSION_ID`가 제공되지 않는 버전/환경에서는 marker의 session_id가 `unknown`으로 기록되어 판정 3에 의해 Stop gate가 상시 통과(비활성)한다. 미차단 방향의 실패이므로 수용하고, 스모크 체크 ③에서 실증된 경우에만 README에 한 줄로 명시한다. 이 환경에서는 `.last-usage`(run 토큰 추정치)도 기록되지 않는다(판정 4 미도달).
- 모든 스크립트 경로는 `${CLAUDE_PLUGIN_ROOT}/scripts/...` 형태로 참조한다.

## 토큰 예산 (하드 제약)

- 상주 표면적(스킬 description + 커맨드/에이전트 description 합계) 300단어 이내
- SKILL.md 본문 500단어 이하, 상세는 references/로 분리해 필요 시에만 로드
- `scripts/check_budget.sh`가 위 둘을 세어 수치 + exit code로 통과/미달을 반환 — 예산 준수는 이 스크립트 출력으로만 증명한다
- verifier 호출은 phase gate(사이클 종료 시점)에만. 매 파일 수정마다 호출 금지
- 결정적/반복적 작업(상태 파일 파싱, 예산 검사, hook 판정, 토큰 추정)은 프롬프트가 아니라 스크립트로 처리

## 핵심 요구사항

1. Maker/Checker 분리: 구현 에이전트와 verifier는 반드시 별도 sub-agent(위 명세 준수). 모든 기준 통과 전까지 루프 종료 불가 — 단, 안전장치 발동 시는 예외로 중단.
2. 스택 불가지론: 루프 로직에 스택 종속 코드 금지. Next.js/TypeScript 프로젝트와 Phaser 3 + Vite 프로젝트 양쪽에서 수정 없이 동작해야 함. 스택 차이는 loop.config.md의 명령어 매핑으로만 흡수.
3. 검증 가능한 정지 조건만 허용: rubric 기준은 전부 명령어 실행 또는 파일 검사로 판정 가능해야 함. "코드가 깔끔하다" 같은 주관 기준 금지.
4. 파일 기반 메모리: 루프의 모든 상태는 `.claude/loop/` 디스크에 존재. 다음 세션이 state.md를 진입점으로 `.claude/loop/`만 읽고 멈춘 지점에서 재개 가능해야 함.
5. 점진 채택: 루프 전체가 아니라 일부만도 사용 가능해야 함 — `--verify-only`(채점만) → `--once`(단일 사이클) → 전체 루프. README에 채택 경로 문서화.

## README 요건

- 설치 2경로:
  - ① marketplace 경유: `/plugin marketplace add <저장소>` → `/plugin install loop-harness@<marketplace>`. marketplace.json은 `.claude-plugin/marketplace.json`에 포함되어 있으므로 이 저장소를 그대로 marketplace로 추가할 수 있음을 명시.
  - ② 로컬 개발: `claude --plugin-dir ./loop-harness` (절대 경로 권장)
- 3분 quickstart — 모든 커맨드를 전체 네임스페이스 형태(`/loop-harness:loop-init` 등)로 표기
- 점진 채택 경로 (`--verify-only` → `--once` → 전체 루프)
- 토큰 비용 주의사항
- 경계 원칙 3가지
- `.claude/loop/` 커밋 정책(임시 파일 제외 전부 커밋 권장)
- 알려진 한계 1줄: `--resume` 세션에서는 session_id 변화로 Stop gate가 비활성일 수 있음
- 알려진 한계 1줄: state.md 미갱신 상태로 중단된 loop-run 세션에서는 다음 턴 종료가 1회 차단될 수 있음(state.md 1줄 기록 후 자연 해소. `--verify-only` 턴이면 read-only 보장 — 지속 파일 기준, 임시 파일 `.last-usage`는 범위 밖 — 의 유일한 예외)
- 알려진 한계(해당 시에만 추가): hook 입력에 `agent_type`이 제공되지 않는(또는 값으로 verifier를 식별할 수 없는) 환경에서는 verifier 쓰기 차단이 `disallowedTools` + 프롬프트 금지 지시로 격하됨
- 알려진 한계(해당 시에만 추가): Bash 환경에 `CLAUDE_CODE_SESSION_ID`가 제공되지 않는(또는 중첩 세션 상속으로 불일치하는) 환경에서는 Stop gate가 비활성(미차단 방향)

## 작업 순서

1. 위 구조대로 플러그인 골격 생성 → 각 파일 작성 (commands → agents → skills → hooks → scripts 순)
2. `check_budget.sh` 실행 → 예산 통과 확인 (미달 시 수정 후 재실행)
3. 도그푸딩 A — 실행 방식을 다음으로 고정한다:
   - 대상 프로젝트 디렉터리에서 headless 중첩 세션으로 실행: `claude -p "<지시 또는 /loop-harness:커맨드>" --plugin-dir <플러그인 절대경로> --permission-mode bypassPermissions`, 호출당 타임아웃 설정(예: 10분)
   - permission mode 주의: headless에서는 권한 프롬프트를 띄울 수 없어 `acceptEdits`로는 모든 Bash 도구 호출이 거부된다(v2.1.201 실측 — 루프·verifier·스모크 체크 전부 불가, 스모크 ② positive test가 권한 계층 거부를 guard deny로 오판하는 위양성 발생). `bypassPermissions`는 일회용 도그푸딩 프로젝트 한정으로 사용한다. hook의 deny는 permission mode와 독립적으로 발화하므로(실측 확인) 스모크 ②의 positive/negative test 전제는 유지된다
   - `-p`에서 커스텀 슬래시 커맨드가 실행되지 않으면, 해당 커맨드 파일 본문을 프롬프트로 직접 전달하는 폴백을 쓰고 그 사실을 memory.md에 `[plugin]` 태그로 기록
   - 비용 통제: 도그푸딩용 rubric은 3~5개, max_iterations는 3으로 설정
   - **스모크 체크 3건 (①②는 loop-init 직후 첫 사이클 진입 전 수행, ③의 일치 대조는 첫 loop-run 턴 종료 후 수행):**
     - ① verifier에게 Read/Grep/Glob/Bash 4개 도구를 각 1회 사용하는 무해한 점검 태스크를 시켜 전부 실사용 가능함을 확인 (tools 목록 첫/마지막 항목 드롭 이슈 방어). 실패 시 목록 순서 조정 등으로 완화 후 memory.md에 `[plugin]` 기록
     - ② verifier에게 의도적으로 `git commit --allow-empty -m test`를 시도시켜 verifier_guard의 deny가 실제 발화함을 확인(positive test)하고, 동시에 메인 에이전트의 동일 명령은 차단되지 않음을 확인(negative test). **이때 deny가 발화하지 않으면 verifier_guard의 `LOOP_GUARD_DEBUG=1` 로그로 원인을 판별한다(로그 없이는 값 불일치와 필드 부재를 구분할 수 없다): 필드 자체가 부재하면 verifier 명세의 폴백을 즉시 적용하고, 필드는 있으나 값이 부분 일치에 걸리지 않으면 로그의 실제 값으로 매칭 문자열을 조정해 1회 재시도한 뒤 그래도 미발화 시 동일 폴백을 적용한다. 두 경우 모두 positive test 요구는 격하 경로(disallowedTools + 프롬프트 금지 지시 + README 명시 + memory 기록)의 이행 확인으로 대체한다.**
     - ③ Bash 환경에 `CLAUDE_CODE_SESSION_ID`가 존재함을 확인한다. 부재 시 `unknown` 폴백(판정 3 fail-open)이 동작함을 확인하고 README 알려진 한계 1줄 + memory.md `[plugin]` 기록. 존재 시에는 첫 loop-run 턴 종료 후 `.run-marker`의 session_id가 stop hook 입력의 session_id와 일치했는지 `LOOP_GUARD_DEBUG=1` 로그로 대조한다(중첩 headless 세션에서 부모 세션 env 상속으로 오염될 가능성 방어). 불일치 시에도 동일하게 README 한계 1줄 + memory 기록(gate는 미차단 방향으로 비활성)
   - 내용: 빈 Next.js 프로젝트(create-next-app, 네트워크 필요) → loop-init → 소형 기능 1개(예: 헬스체크 API + 테스트)를 goal로 설정 → 루프 실행 → verifier 채점, state/memory/review 갱신 확인
4. A 중 세션 재개 테스트: 루프 중간에 자식 프로세스를 timeout/kill로 강제 종료 → 새 headless 세션에서 `/loop-harness:loop-status` → `.claude/loop/`만으로 멈춘 지점부터 재개되는지 확인. 이때 잔존 .run-marker(타 세션 session_id) 때문에 새 세션의 종료가 차단되지 않는지 함께 확인
5. A 중 안전장치 테스트: 의도적으로 통과 불가능한 기준 1개를 rubric에 넣고, 3회 연속 실패 시 에스컬레이션이 실제 발동하는지 확인. headless에서는 "에스컬레이션 옵션 출력 + state.md 중단 사유 기록 + 종료"가 확인 대상이다. (확인 후 해당 기준 제거)
6. 도그푸딩 B: Phaser 3 + Vite 프로젝트에서 3번 절차 반복
7. 도그푸딩에서 발견된 문제를 memory.md 5단계 프로토콜로 기록하며 플러그인 수정(플러그인 자체를 루프로 개선). 기록에 `[plugin]`(하네스 결함) / `[project]`(대상 프로젝트 결함) 태그를 붙여 distill 단계 오염 방지
8. 클린 재실행: 모든 수정 완료 후 A/B 도그푸딩을 처음부터 다시 실행해 **플러그인 로직 수정 0회**(문서·주석·README 수정은 로직 수정으로 계상하지 않음)로 통과하는지 확인. 네트워크·패키지 레지스트리·스캐폴딩 도구 버전 등 플러그인 외부 요인으로 인한 실패는 실패 횟수에 계상하지 않고 해당 단계만 재시도한다(외부 요인 여부는 에러 원인을 state.md에 기록해 구분). 최대 3회 시도, 초과 시 실패 원인을 정리해 사람에게 보고하고 중단

## 수용 기준 (전부 충족해야 완료)

- [ ] 신규 프로젝트 적용 절차 = 설치 1회 + loop-init 1회. README에 설치 2경로(marketplace add 단계 포함) 문서화
- [ ] verifier가 독립 컨텍스트에서 채점하며, Write/Edit 미부여 + `disallowedTools` 명시 + `agent_type` 스코프(부분 일치, 필드 부재 시 fail-open) PreToolUse 가드가 실제 구성됨 — verifier의 쓰기성 Bash는 deny로 실차단되고(positive test), 메인 에이전트의 동일 명령은 차단되지 않음을 실증. **단, 스모크 체크에서 `agent_type` 필드 부재 또는 값 불일치(매칭 문자열 조정 1회 재시도 후에도 deny 미발화)가 실증된 환경에서는 폴백(guard 비활성 + disallowedTools + 프롬프트 금지 지시 + README 한계 명시 + memory 기록) 이행으로 이 기준을 충족한다**
- [ ] verifier가 frontmatter의 4개 도구(Read/Grep/Glob/Bash)를 전부 실사용 가능함 (작업 순서 3 스모크 체크로 실증)
- [ ] rubric 체크박스/state.md 갱신 주체가 메인 에이전트로 일관 (verifier는 리포트만 반환)
- [ ] rubric의 모든 기준이 기계적으로 검증 가능
- [ ] 세션 강제 종료 후 재시작 시 `.claude/loop/`만으로 이어서 실행 가능 (작업 순서 4로 실증)
- [ ] max_iterations + 3회 연속 실패 에스컬레이션이 작동함 — headless 기준: 옵션 출력 + 사유 기록 + 종료 (작업 순서 5로 실증)
- [ ] 클린 재실행에서 Next.js/Phaser 양쪽 도그푸딩 통과 — 플러그인 로직 수정 0회(문서·주석 제외), 외부 요인 실패는 재시도로 처리하고 원인을 state.md에 기록
- [ ] check_budget.sh 통과 (상주 300단어, SKILL.md 본문 500단어) — 출력 첨부
- [ ] 매 사이클 review.md 생성됨 (comprehension debt 대응)
- [ ] memory.md에 5단계 진행 흔적(fail→distill)과 [plugin]/[project] 태그가 실제 기록됨
- [ ] state.md가 100줄 상한 내에서 요약 갱신되고 run별 토큰 추정치(stop_gate.sh 산출)가 기록됨. 단, 스모크 체크 ③에서 session_id 획득 불가가 실증된 환경에서는 README 한계 명시로 대체 충족
- [ ] Stop hook 3중 가드 검증: ① 루프 무관 세션 비차단 ② stop_hook_active 시 비차단 ③ 잔존 마커(타 세션) 비차단. 단, 스모크 체크 ③에서 session_id 획득 불가·불일치가 실증된 환경에서는 "gate 비활성 + README 한계 명시"의 문서화로 대체 충족
- [ ] `--verify-only`가 기존 코드에 대해 채점 리포트만 출력하고 아무 파일도 수정하지 않음(`.run-marker` 미기록 포함) + Stop gate에 차단되지 않음 — 잔존 marker 없는 신선한 세션 기준으로 검증(알려진 한계 2의 예외 참조)
- [ ] plugin.json에 version, `.claude-plugin/`에 marketplace.json, 루트에 CHANGELOG.md 존재
- [ ] README에 quickstart(전체 네임스페이스 표기) + 점진 채택 경로 + 경계 원칙 3가지 포함

## 사전 질문

구현 전 궁금한 점(대상 스택, 이슈 트래커/CI 등)은 한 번에 질문하라. 답을 받지 못하면 다음 기본값을 명시하고 진행한다: 언어 스택 무관(loop-init이 감지 — 대화형에서만 감지 실패 시 질문, 비대화형에서는 TODO placeholder 기록 후 진행), 이슈 트래커·CI 연동 없음, test/lint/build 명령은 loop-init이 감지(package.json scripts, pyproject.toml, Makefile, Cargo.toml 등 생태계별 매니페스트)·질문해 loop.config.md에 기록.

## 진행 규칙

- 각 단계 완료 시 산출 파일 경로와 수용 기준 체크 상태를 보고할 것
- 불명확한 결정은 추측하지 말고 옵션 2~3개 + 트레이드오프로 질문할 것
- 수용 기준 미충족 상태에서 "완료" 선언 금지

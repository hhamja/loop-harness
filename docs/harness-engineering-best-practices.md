# 하네스 엔지니어링 베스트 프랙티스 — Claude Code · Codex

> 하네스 엔지니어링: 프롬프트가 아니라 **에이전트를 둘러싼 소프트웨어**(지침 파일·도구·훅·피드백 루프·환경)를 설계해 출력 품질과 신뢰성을 높이는 실천.
> 엔지니어의 일은 "코드 작성"에서 "환경 설계 + 의도 명세 + 피드백 루프 구축"으로 이동한다. (Anthropic·OpenAI 공통 결론)

## 공통 원칙 (양사 수렴점)

1. **컨텍스트는 희소 자원** — 지침 파일은 "지도(map)"이지 "1,000쪽 매뉴얼"이 아님. 부풀면 지침이 실제로 무시됨.
2. **기계 검증 가능한 완료 정의** — 테스트·빌드·스크립트가 pass/fail 신호를 줘야 에이전트 루프가 스스로 닫힘. "봐서 완료 같음"이 유일한 신호면 사람이 검증 루프가 됨.
3. **maker/checker 분리** — 에이전트는 자기 작업을 과하게 후하게 채점함. 독립 Evaluator/리뷰어(신선한 컨텍스트)로 분리.
4. **상태는 디스크에** — feature list·진행 노트·git 히스토리로 새 세션이 파일만 읽고 즉시 복구. 컨텍스트 윈도우에 상태를 두지 말 것.
5. **결정론이 필요하면 훅** — "매번 반드시" 일어나야 하는 것(포맷·린트·승인 게이트)은 모델의 기억이 아니라 훅에. 지침 파일은 advisory, 훅은 guarantee.
6. **하나의 작업 단위, 하나의 기능** — 전체 프로젝트를 한 작업으로 던지지 말고 검증 가능한 청크로 분해.
7. **모델이 좋아지면 하네스를 단순화** — 하네스의 각 구성요소는 "모델이 못 하는 것"에 대한 가정이며, 그 가정은 만료됨. 릴리스마다 스캐폴딩 재평가.
8. **강한 아키텍처 제약이 속도의 전제** — 제약이 있어야 드리프트 없이 빠르게 감. (OpenAI: 수 주 만에 100만 줄)

## Claude Code (Anthropic)

### 지침·환경
- **CLAUDE.md는 짧게**: 코드에서 유추 불가한 것만(빌드 명령·스타일 예외·레포 관례·환경 특이점). 각 줄에 "이게 없으면 실수하나?" 질문, 아니면 삭제. `/init`으로 시작.
- 가끔만 필요한 지식·워크플로는 **Skills**(`SKILL.md`)로 — 온디맨드 로드라 매 세션 컨텍스트를 안 잡아먹음.
- **훅**으로 결정론적 강제(edit 후 lint, 민감 경로 write 차단). 권한 allowlist·auto mode·샌드박스로 중단 최소화.

### 워크플로
- **Explore → Plan → Code → Commit**: plan mode로 탐색·계획을 구현과 분리. 한 문장으로 diff를 설명할 수 있으면 계획 생략.
- **검증 수단을 항상 제공**: 테스트 케이스, 스크린샷 비교, `/goal` 조건, Stop hook 게이트, 검증 서브에이전트. 성공 주장 대신 **증거**(테스트 출력·스크린샷)를 요구.
- **컨텍스트 공격적 관리**: 작업 전환마다 `/clear`, 조사·리뷰는 서브에이전트로 위임(별도 컨텍스트), 두 번 교정에 실패하면 `/clear` 후 더 나은 프롬프트로 재시작.
- **스케일**: `claude -p`(headless)로 CI·fan-out, worktree 병렬 세션, Writer/Reviewer 패턴(신선한 컨텍스트가 리뷰 편향 제거), 완료 전 적대적 리뷰 서브에이전트.

### 장기 실행 하네스 (long-running agents)
- **Initializer / Coding Agent 이원화**: 첫 컨텍스트 윈도우 전용 프롬프트로 환경 구축(git init, `init.sh`, feature list), 이후 세션은 동일 Coding Agent.
- **Feature list(JSON, `passes: false`)**: 요청을 세부 기능 체크리스트로 확장, 에이전트가 편집 못 하게 강제 → 조기 "완료 선언" 차단.
- **세션 시작 프로토콜**: git log + 진행 파일(`claude-progress.txt`) 읽기 → `init.sh`로 서버 기동 → 기본 E2E 테스트 → 미완료 기능 하나 착수. 종료 시 커밋 + 진행 노트.
- **compaction보다 context reset**: 파일 기반 핸드오프로 컨텍스트를 통째로 초기화하는 편이 일관성에 유리 (최신 모델일수록 완화).
- **Planner / Generator / Evaluator 분리**(GAN식): Evaluator가 Playwright 등으로 실제 사용자 흐름을 테스트하고 구체적 피드백 반환. 완료 기준은 사전에 계약(Sprint Contract).

## Codex (OpenAI)

### 지침·설정
- **AGENTS.md는 계층으로**: `~/.codex/AGENTS.md`(개인 전역) → 레포 루트 → 하위 디렉토리 override(하위가 상위를 덮음). 기본 32KiB 제한 — 넘치면 중첩 디렉토리로 분산.
- 넣을 것: working agreement(예: "JS 수정 후 반드시 `npm test`"), 빌드/테스트 명령, 완료 기준, 승인 절차. 뺄 것: 장황한 설명, 기술스택 설정(→ `config.toml`).
- **`config.toml`로 일관성**: 모델·reasoning effort·sandbox mode·승인 정책을 개인/레포 단위로 고정.
- 프롬프트에서 반복되는 임시 규칙은 즉시 AGENTS.md로 승격.

### 워크플로
- **프롬프트 4요소**: Goal / Context / Constraints / **Done when**(완료 기준).
- 복잡한 변경은 **plan mode**(`/plan`) + `PLANS.md` 템플릿으로 계획 먼저. reasoning effort는 작업 난이도에 맞춰 선택.
- **신뢰성 루프**: 테스트 작성·실행 + lint/format/typecheck + `/review`(base branch 비교) + `code_review.md`로 리뷰 기준 정의 + PR 자동 리뷰.
- 반복 워크플로는 **Skills**(`.agents/skills/SKILL.md`)로 패키징 — 한 작업에 scoped, 입출력 명확히.
- **worktree로 실파일 보호**, subagent로 제한된 작업 분리, 안정화 후에만 scheduled task 자동화.
- 훅은 반복 강제의 집: AGENTS.md에 적는 것보다 훅이 확실함 (포맷·린트·민감 명령 승인·PR 생성).

### 안티패턴 (공식 문서 명시)
- 빌드/테스트 명령을 안 알려줌 · 복잡한 작업에서 계획 생략 · 이해 전 전체 권한 부여 · worktree 없이 실파일 작업 · 전체 프로젝트를 한 작업으로 · 임시 규칙을 프롬프트에 방치.

## 출처

- Anthropic, [Effective harnesses for long-running agents](https://www.anthropic.com/engineering/effective-harnesses-for-long-running-agents)
- Anthropic, [Harness design for long-running application development](https://www.anthropic.com/engineering/harness-design-long-running-apps)
- Anthropic, [Claude Code best practices](https://code.claude.com/docs/en/best-practices)
- OpenAI, [Harness engineering: leveraging Codex in an agent-first world](https://openai.com/index/harness-engineering/)
- OpenAI, [Codex best practices](https://developers.openai.com/codex/learn/best-practices)
- OpenAI, [Custom instructions with AGENTS.md](https://developers.openai.com/codex/guides/agents-md)

# 하네스 엔지니어링 베스트 프랙티스 — Claude Code · Codex

> 하네스 엔지니어링: 프롬프트가 아니라 **에이전트를 둘러싼 소프트웨어**(지침 파일·도구·훅·피드백 루프·환경)를 설계해 출력 품질과 신뢰성을 높이는 실천.
> 엔지니어의 일은 "코드 작성"에서 "환경 설계 + 의도 명세 + 피드백 루프 구축"으로 이동한다. (Anthropic·OpenAI 공통 결론)

## 핵심 원칙

1. **컨텍스트는 희소 자원, 구조화된 파일이 해법** — 세션 간 간극은 디스크 산출물로 잇는다. 지침 파일은 "지도(map)"이지 백과사전이 아님(~100줄) — 부풀면 실제로 무시됨.
2. **기계 검증 가능한 완료 정의** — "done"은 통과하는 체크(테스트 green, exit 0, 파일 존재)이지 에이전트의 자기 판단이 아님.
3. **maker/checker 분리** — 에이전트는 자기 작업을 후하게 채점함. 독립 Evaluator를 회의적으로 튜닝하는 게 Generator를 자기비판적으로 만드는 것보다 훨씬 쉬움.
4. **레포가 시스템 오브 레코드** — 에이전트가 컨텍스트에서 접근 못 하는 지식은 존재하지 않는 것. Slack 결정·아키텍처 패턴·제품 맥락을 전부 레포로.
5. **한 세션 한 작업** — 컨텍스트 고갈을 막고 세션을 복구 가능하게 유지.
6. **빠른 피드백 루프 = 백프레셔** — 잘못된 출력을 거부하는 모든 것(타입체커·린터·테스트·UI 자동화)을 루프에 배선. 검증이 느리면 반복 횟수가 줄어듦.
7. **모든 루프에 한계를** — 반복 상한 + 예산 한도 + 기계 검증 정지 조건 + 사람 에스컬레이션 경로. 무한 루프가 가장 비싼 실패 모드.
8. **결정론이 필요하면 훅** — 지침 파일은 advisory, 훅은 guarantee. "매번 반드시"는 모델 기억에 맡기지 말 것.
9. **단순하게 시작, 한계에 부딪힐 때만 복잡화** — 단일 에이전트 루프가 멀티 에이전트보다 먼저. 모델이 좋아지면 스캐폴딩을 걷어내라(하네스의 각 부품은 "모델이 못 하는 것"에 대한 가정이고, 그 가정은 만료됨).

## 하네스 구축 프랙티스

### 아키텍처
- **단일 루프로 시작** — 멀티 에이전트는 마이크로서비스 복잡도 + 비결정성. 구체적 한계에 부딪힐 때만 도입.
- 도입 시 역할 분리: **Planner**(짧은 프롬프트 → 스펙, 과잉 명세 금지) / **Generator**(한 번에 한 기능) / **Evaluator**(실제 사용자처럼 테스트, 구체적 피드백 반환).
- **compaction보다 context reset** — 세션마다 새 컨텍스트 + 파일 기반 핸드오프가 "context anxiety"(조기 마무리)를 제거. 최신 모델일수록 완화되므로 재평가.

### 상태·세션
- 디스크에 둘 것: **task list(JSON, `passes:false`)** — Markdown보다 손상에 강함, 삭제·재정렬 금지·상태 플립만 / **진행 노트** / **spec 파일** / **init 스크립트** / **git 히스토리**(서술적 커밋).
- **세션 프로토콜**: 진행 노트·git log 읽기 → init 실행 → **baseline 검증**(이전 세션이 깨뜨렸을 수 있음 — 만들기 전에 확인) → 미완료 작업 하나 선택 → 구현 → 실제 UI/API로 테스트 → 상태 갱신·커밋·노트 → 동작하는 상태로 종료.

### 피드백 루프·평가
- 구현 직후 해당 단위의 테스트를 즉시 실행. **UI 자동화**(Playwright/Puppeteer)로 실제 흐름 검증 — 강제하지 않으면 테스트 없이 완료 표시함.
- Evaluator에는 "좋은가?"가 아니라 **채점 가능한 기준**: 기준 정의 + few-shot 캘리브레이션 예시 + 하드 실패 임계값. 가중치는 모델이 약한 영역(독창성·기능 완결성)에.
- 복잡한 작업은 **Sprint Contract** — 구현 전 Generator·Evaluator가 "done"의 정의를 협상.

### 컨텍스트 관리
- 메인 컨텍스트는 **스케줄러**로 — 검색·분석·요약은 서브에이전트로 오프로드. 읽기는 고병렬 fan-out, 쓰기(빌드·테스트)는 병렬 제한. 원시 출력 대신 요약만 반환.
- 매 루프 동일한 핵심 파일(plan·spec)을 결정론적으로 로드.
- **"코드가 없다고 가정하지 말 것"** — 에이전트의 검색은 불완전. 구현 전 기존 코드 검색을 지시해 중복 구현 방지.

### 프롬프트
- **스텁/placeholder 금지를 명시** — 에이전트는 "컴파일만 되는" 최소 구현으로 기울어짐. 강한 언어로 완전 구현 강제.
- 결정의 **"왜"를 문서화**하게 지시 — 미래 루프에는 원래 추론이 없음.
- 에이전트가 지침 파일(AGENTS.md/CLAUDE.md)을 **스스로 개선**하도록 허용 — 명령을 여러 번 틀렸으면 다음 루프가 반복하지 않게 기록.
- 발견한 버그는(무관해도) 즉시 todo에 기록.

### 보안 (3계층 방어)
- OS 샌드박스 + 파일시스템 제한(프로젝트 디렉토리로) + 명령 allowlist(제대로 된 shell lexer로 파싱, 파이프·체이닝 처리, 민감 명령 추가 검증).

### 코드베이스 설계 (에이전트 가독성)
- 불변식은 문서가 아니라 **기계로 강제**: 린트 규칙을 코드로, 에러 메시지에 교정 방법 포함(사람 개입 없이 자가 수정).
- **기술부채는 GC처럼** — 정기 청소 에이전트가 원칙 이탈을 스캔하고 소규모 리팩토링 PR.
- **boring tech 선호**(학습 데이터에 잘 표현된 안정 API), 앱을 에이전트가 검사 가능하게(worktree별 부팅, DevTools 연결, 조회 가능한 로그/메트릭).

### 복구·정지 조건
- 루프 시작 전 정의: **반복 상한 · 토큰/달러 예산 · 기계 검증 성공 기준 · N회 연속 무진전 시 사람 에스컬레이션**.
- **git이 안전망**: 작업마다 커밋, 세션 시작 시 히스토리 읽기, known-good에 태그, 깨지면 `reset --hard` 후 재실행. "리셋 후 재실행 vs 현 상태 구조" 둘 다 유효한 전략.
- **계획을 주기적으로 재생성** — todo·plan은 드리프트함. 코드베이스를 스펙과 비교해 삭제·재생성.

## Claude Code (Anthropic) 구체 기법

- **CLAUDE.md는 짧게**: 코드에서 유추 불가한 것만. 각 줄에 "없으면 실수하나?" — 아니면 삭제. `/init`으로 시작. 가끔 필요한 지식은 **Skills**(온디맨드 로드)로.
- **Explore → Plan → Code → Commit**: plan mode로 탐색·계획을 구현과 분리. diff를 한 문장으로 설명 가능하면 계획 생략.
- 검증 수단: 테스트 케이스 명시, 스크린샷 비교, `/goal` 조건, Stop hook 게이트, 검증 서브에이전트. 성공 주장 대신 **증거** 요구.
- 컨텍스트: 작업 전환마다 `/clear`, 교정 2회 실패 시 `/clear` 후 더 나은 프롬프트로 재시작.
- 스케일: `claude -p`(headless)로 CI·fan-out, worktree 병렬, Writer/Reviewer 패턴, 완료 전 적대적 리뷰 서브에이전트.
- 장기 실행: **Initializer/Coding Agent 이원화** — 첫 컨텍스트 윈도우 전용 프롬프트로 환경 구축(git init, `init.sh`, feature list), 이후 세션은 동일 프로토콜 반복.

## Codex (OpenAI) 구체 기법

- **AGENTS.md 계층**: `~/.codex/AGENTS.md`(전역) → 레포 루트 → 하위 override(하위 우선). 기본 32KiB — 넘치면 중첩 디렉토리로 분산. 프롬프트에 반복되는 임시 규칙은 즉시 승격.
- 넣을 것: working agreement·빌드/테스트 명령·완료 기준·승인 절차. 뺄 것: 장황한 설명, 기술스택 설정(→ `config.toml`).
- **프롬프트 4요소**: Goal / Context / Constraints / **Done when**.
- 복잡한 변경은 plan mode(`/plan`) + `PLANS.md`. 신뢰성 루프: 테스트 + lint/typecheck + `/review`(base branch 비교) + `code_review.md` 리뷰 기준.
- 반복 워크플로는 Skills(`.agents/skills/`)로 — 한 작업에 scoped. worktree로 실파일 보호, 안정화 후에만 scheduled task.
- 안티패턴(공식 명시): 빌드 명령 미기재 · 계획 생략 · 이해 전 전권 부여 · worktree 없이 실파일 · 전체 프로젝트를 한 작업으로 · 임시 규칙 방치.

## 출처

- Anthropic, [Effective harnesses for long-running agents](https://www.anthropic.com/engineering/effective-harnesses-for-long-running-agents)
- Anthropic, [Harness design for long-running application development](https://www.anthropic.com/engineering/harness-design-long-running-apps)
- Anthropic, [Claude Code best practices](https://code.claude.com/docs/en/best-practices)
- OpenAI, [Harness engineering: leveraging Codex in an agent-first world](https://openai.com/index/harness-engineering/)
- OpenAI, [Codex best practices](https://developers.openai.com/codex/learn/best-practices)
- OpenAI, [Custom instructions with AGENTS.md](https://developers.openai.com/codex/guides/agents-md)
- Geoffrey Huntley, [Ralph Wiggum as a "software engineer"](https://ghuntley.com/ralph/)
- 사용자 제공 통합 정리본 (`agent-harness-best-practices.md`)

# loopy 하네스 엔지니어링 — 점검 결과 및 구축 계획

> 2026-07-11, 기준 커밋 5e3e558 (main, tamper_gate 92d7144 랜딩 반영 — 초안은 81a2b8e 기준이었음). 레퍼런스: 자율 에이전트 하네스 & 루프 아키텍처 문서와의 비교 분석.
> 사용자 결정: **루프 레이어 보류, 하네스 레이어 우선** — 하네스 설계 점검 후 하네스부터 설계·구축.
> 근거: 레퍼런스 §9와 loopy 자신의 loop-control-plane.md §9 모두 하네스 우선을 명시 (자율 반경의 두 인수 = 검증기 신뢰도 × 되돌림 가능성, 둘 다 하네스 속성).

## Context

레퍼런스 아키텍처 문서와 loopy를 비교해 보완점 5개를 도출했고(이전 분석), 그중 하네스 레이어(정적: hooks, verifier, rubric 포맷, subagent)에 속하는 갭만 이번에 구축한다. 루프 레이어 갭(park-and-continue, wall-clock 상한, /goal 엔진)은 보류 목록으로 이관.

## Phase A — 하네스 설계 점검 결과 (완료, 추가 감사 불필요)

`docs/harness-review.md`(직전 커밋의 종합 셀프 리뷰) + 이번 레퍼런스 비교를 합친 평가:

**잘된 것 (레퍼런스 요구보다 강하거나 동등):**
- verifier가 `verify:` 명령을 **직접 실행**하는 채점자 (레퍼런스의 /goal 평가자보다 강한 진실 기준) — C PASS
- maker/checker 분리 + 크로스모델(Codex maker/Claude verifier) + verifier_guard 훅 백스톱
- T0/T1/T2 비가역성 분류, decision_gate(0.14.0부터 전역), worktree 격리, branch_guard
- 디스크 상태(state/memory/rubric) + check_memory 위생 게이트, 예산 CI, 셀프 감사 문화

**갭 (ETCLOVG 판정 + 레퍼런스 렌즈):**
| 갭 | 판정 | 출처 |
|---|---|---|
| **출구**: done 선언 시 verifier verdict 미검사 (stop_gate.sh:70은 state.md 신선도만) | V PARTIAL | 레퍼런스 MUST, 신규 |
| **입구**: 스펙→rubric 컴파일·사람 승인·판정불가 에스컬레이션 부재 | — | 레퍼런스 "사람의 진짜 일", 신규 |
| rubric 동결 게이트가 과잉 — tamper_gate(92d7144)가 rubric.md **전체**를 블랭킷 deny, 정상 플로우(apply-report 체크박스 갱신·spec 컴파일)까지 차단. verify: 라인 약화만 막는 세분화 필요 | V PARTIAL | roadmap 5는 구현됨(tamper_gate), 세분화가 신규 |
| holdout 스위트 없음 (정보 비대칭 0) | L4 상한 사유 | 알려진 roadmap 4 — 이번 범위 밖 |
| observability 카운터 1/4 | O FAIL | 알려진 roadmap 6 — 이번 범위 밖 |

**결론: 성숙도 L3/5. 하네스의 뼈대(검증·격리·분리)는 견고하고, 남은 것은 입구·출구 게이트 + 동결 강제.**

## Phase B — 하네스 구축 계획 (구현 3건, 작은 것부터)

### H1 · verifier-green Stop 게이트 (출구) — `scripts/stop_gate.sh`
- apply-report 단계에서 메인 에이전트가 `.claude/loop/.verifier-verdict` 기록 (`verdict=N/M`, `session_id=`, `ts=` — 기존 `field()` key=value 포맷, verifier는 읽기 전용 유지).
- stop_gate.sh에 **verdict 5** 추가 (verdict 4 통과 후):
  - `human_gate: ready_for_merge` → verdict 파일이 없거나 `.run-marker`보다 오래됐거나(기존 `[ A -ot B ]` 관용구) N<M이면 **block**.
  - `loop_active: true` + `human_gate: none` → verdict 파일 부재/stale일 때만 block (fresh한 failing verdict는 정상 중간 정지 — pass).
  - `stalled`/`pending_t2`/`needs_branch`/미지 값/필드 부재 → 전부 fail-open. `stop_hook_active`(verdict 2)가 재프롬프트 1회 상한이라 오탐 비용은 nudge 1회.
- 구현 노트: stop_gate는 현재 state.md 내용을 읽지 않음(mtime 신선도만) — `human_gate:`/`loop_active:` 파싱은 drive_next.sh의 기존 state.md 관용구를 미러(공용화는 구현 시 판단).
- 수정 파일: `scripts/stop_gate.sh`(+~20줄), `skills/loop-run/references/apply-report.md`(verdict 기록 스텝 — preflight 마커 블록 미러), `.gitignore`는 기존 블랭킷 `.claude/` 룰이 커버.
- 테스트(`tests/run.sh` test_stop_gate 기존 7케이스에 +7): ready_for_merge×{파일 없음→block, 5/5 fresh→pass, 3/5→block, stale→block}, loop_active×{verdict 없음→block, failing fresh→pass}, stalled×없음→pass. 기존 픽스처는 필드 부재 fail-open으로 전부 생존(확인됨 — 픽스처 state.md에 두 필드 자체가 없음).

### H2 · rubric 동결 세분화 (roadmap 5 후속) — 기존 `scripts/tamper_gate.sh` 수정
- **전제 갱신**: tamper_gate(92d7144, PreToolUse `Edit|Write|NotebookEdit`, hooks.json:18)가 이미 rubric.md **전체** 쓰기를 T2 deny (tamper_gate.sh:46) — roadmap 5는 구현됨. 남은 문제는 반대 방향: 블랭킷 deny가 정상 플로우(apply-report의 `[x]` 체크박스 갱신, H3 loop-spec의 rubric 컴파일)까지 차단.
- **변경**: tamper_gate의 rubric.md 암만 세분화 — `old_string`(또는 Write 시 기존 파일 내용 diff)이 기존 `verify:` 라인을 변경·삭제하는 경우만 deny, 체크박스 토글·기준 **추가**는 allow. 강화는 자유, 약화만 게이트.
- 신규 freeze_gate.sh는 만들지 않음 — 같은 matcher에 두 훅이 돌면 어느 한쪽 deny로 차단되므로, tamper_gate 블랭킷이 살아있는 한 별도 게이트의 allow는 발효 불가(데드 코드).
- 나머지는 현행 유지: tests/·.github/workflows/·scripts/·hooks/·`.gate-approved` 암은 블랭킷 그대로, 활성 조건도 always-on 유지(loop-independent가 설계 철학, tamper_gate.sh:15 — loop_active 조건으로 좁히면 기존 게이트 약화). 탈출구는 기존 `gate_approved()`(hook_lib.sh:130, decision_gate와 공유) 그대로.
- **에스컬레이션(구현 안 함)**: tests/·workflows/ 세분화 — TDD 중 테스트 수정은 정상 작업이라 기계 판정 불가. 마찰이 실측되면 PR 논의로 (0.14.0 원칙: 기계 검증 불가 조건 게이트는 러버스탬프).
- 수정 파일: `scripts/tamper_gate.sh`, `docs/harness-review.md` roadmap 5 상태 갱신. hooks.json 변경 없음.
- 테스트(기존 tamper 13개에 +5): verify: 라인 수정→deny, verify: 라인 삭제→deny, 체크박스만 수정→allow, 기준 추가→allow, 승인 마커 유효→allow.

### H3 · loop-spec 스킬 (입구) — 신규 `skills/loop-spec/`
- `disable-model-invocation: true`, `argument-hint: "[PRD file or inline spec text]"`. 흐름: PRD/텍스트 → 요구별 `R#: … — verify: <command>` 컴파일(기준은 기존 `loop-engineering/references/rubric-guide.md` 참조, 중복 금지) → **컴파일 불가 요구는 rubric.md `## Escalated — not machine-verifiable` 섹션에 질문+옵션 2-3개로 기록, 절대 조용히 해석 안 함** → `approved: pending` 키 라인, 인터랙티브면 질문 1개로 승인 확정(`approved: <name> <date>`), headless면 pending 유지.
- loop-init 비차단 철학 유지: init은 스캐폴드, spec은 채움, run은 preflight에서 미승인/Escalated 잔존 시 **경고만**(하드 게이트 금지 — 0.14.0 원칙). `approved:` 라인 자체가 없는 레거시 rubric은 침묵(fail-open).
- 기존 rubric 병합 시 기존 기준 삭제·약화 금지 (replan.md one-rule이 이 스킬에도 적용) — H2 게이트가 이를 기계 백업.
- **H2 의존**: loop-spec의 rubric 쓰기(기준 추가)는 현행 tamper_gate 블랭킷 deny에 걸림 — H2 세분화 이후에만 통과 가능. 구현 순서 H2 → H3 필수.
- 예산: description +14단어 → 281/300 (확인됨). 본문 ≤500단어 자체 한도.
- 수정 파일: `skills/loop-spec/SKILL.md`(신규), `skills/loop-run/references/preflight.md`(+2줄 경고).

## 구현 순서·방식

1. **H1** (셸+골든 테스트, 의존성 없음) → 2. **H2** (기존 tamper_gate 수정, 신규 표면 없음) → 3. **H3** (유일한 신규 상주 표면, H2에 의존, 마지막).
- 각 단계 독립적으로 `bash scripts/ci_local.sh` green → 개별 커밋. 브랜치: `feat/universal-gates`에서 진행하거나 신규 `feat/harness-gates` (현재 트리 clean).
- H1·H2는 기계 검증 가능한 셸 작업이라 **loopy 루프 dogfooding 적합** (rubric 기준 = 위 테스트 케이스). 단 현재 `.claude/loop/state.md`가 `human_gate: ready_for_merge`(이전 review/gate-fixes 대기)이므로 루프로 돌릴 경우 state 초기화가 선행 — 아니면 직접 구현(global CLAUDE.md §6 예외 범위엔 안 맞지만 플러그인 자기 수정 + 골든 테스트가 verifier 역할).

## 보류 (루프 트랙 — 하네스 완료 후)

- GAP-3 park-and-continue 에스컬레이션 (replan.md 재작성 + state.md `## Parked`)
- GAP-5 무인 wall-clock 상한 (drive_next.sh +8줄)
- GAP-4 네이티브 /goal 엔진 — docs 결정 단락으로 에스컬레이션 (H1의 verdict 파일이 미래 컴파일 타깃)
- holdout(roadmap 4)·observability(roadmap 6) — 기존 로드맵 유지

## Verification

- 단계별 `bash scripts/ci_local.sh` (budget + 골든 테스트) — CI와 동일.
- H1: `bash tests/run.sh`로 신규 7케이스 + 기존 stop_gate 7케이스 전부 green.
- H2: 기존 tamper 13케이스 + 신규 5케이스 green + 수동 시나리오(rubric verify: 라인 Edit 시도 → deny JSON, 체크박스 Edit → 통과 확인).
- H3: `bash scripts/check_budget.sh` → `BUDGET OK` (281/300 예상), 샘플 PRD로 스킬 실행해 Escalated 섹션·approved 라인 생성 확인.

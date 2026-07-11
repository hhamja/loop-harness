# loopy — 프로젝트 지도

Claude Code 루프 엔지니어링 플러그인: maker/checker 분리로 "done"을 기계 검증한다.
개요·설치·사용법은 [README.md](README.md), 변경 이력은 [CHANGELOG.md](CHANGELOG.md).

## 규칙

- **네이티브 프리미티브 우선** (수작업·임시방편 대신): skills, hooks, permission rules, subagent, worktree, MCP, plugins/marketplace, sandbox.
- **신규 기능은 Skill로** (`skills/<name>/SKILL.md`), Command 아님(레거시). 부수효과 워크플로는 `disable-model-invocation: true`, 인자는 `argument-hint` + `$ARGUMENTS`.
- **로컬 관례 < 공식 베스트 프랙티스** — 충돌하면 명시하고 공식을 기본값으로. "기존 파일이 X를 쓴다"는 X의 근거가 아니다.
- **예산(CI 강제):** 모든 `description:` 합계 ≤ 300단어, 각 `skills/*/SKILL.md` 본문 ≤ 500단어. 증거는 `bash scripts/check_budget.sh` → `BUDGET OK`.
- **커밋 전 검증:** `bash scripts/ci_local.sh` — CI와 동일한 체크를 로컬에서 먼저.
- **언어:** 운영 파일(SKILL·에이전트·스크립트·README)은 영어, 채팅 리포트는 한국어.

## 구조

| 위치 | 내용 |
|---|---|
| `skills/` | 기능 진입점 — `/loopy:loop-*` 스킬 8종 (init, run, status, review, audit, ci, worktree, engineering) |
| `agents/` | 읽기 전용 서브에이전트 5종 (verifier, auditor, design-critic, explorer, loop-architect) |
| `scripts/` | 훅·게이트 셸 스크립트 — 공용 config/JSON 파싱은 `hook_lib.sh` 단일 소스 |
| `hooks/hooks.json` | 훅 배선 — 게이트는 망각 백스톱이지 샌드박스가 아님 (위협 모델: docs/harness-review.md) |
| `tests/` | 골든 테스트 — `bash tests/run.sh` |
| `.claude/loop/` | (대상 프로젝트 측) 모든 가변 상태 — 플러그인 자체는 불변 로직 |

## 심층 문서 (docs/)

- [loop-control-plane.md](docs/loop-control-plane.md) — 루프 설계 원리(자율 반경 = 검증기 신뢰도 × 되돌림 가능성, ETCLOVG). **설계 변경 전 필독.**
- [harness-review.md](docs/harness-review.md) — loopy 셀프 리뷰 결과·위협 모델·미해결 에스컬레이션. **게이트 수정 전 필독.**
- [harness-review-rulebook.md](docs/harness-review-rulebook.md) — 하네스 엔지니어링 룰북 (리뷰 판정 기준, 규칙 ID·심각도·Claude Code 매핑).

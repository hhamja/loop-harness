# loopy — 프로젝트 지침

- **신규 기능은 Skill로** (`skills/<name>/SKILL.md`), Command 아님 — 공식상 커스텀 커맨드는 Skill로 통합됨(호출은 `/loopy:<name>`으로 동일). 부수효과 워크플로는 `disable-model-invocation: true`, 인자는 `argument-hint` + `$ARGUMENTS`. `commands/`는 레거시.
- **로컬 관례 < 공식 베스트 프랙티스** — 충돌하면 명시하고 공식을 기본값으로. "기존 파일이 X를 쓴다"는 X의 근거가 아니다.
- **예산(CI 강제):** 모든 `description:` 합계 ≤ 300단어, 각 `skills/*/SKILL.md` 본문 ≤ 500단어. 증거는 `bash scripts/check_budget.sh` → `BUDGET OK`.
- **언어:** 운영 파일(SKILL·커맨드·에이전트·스크립트·README)은 영어, 채팅 리포트는 한국어.

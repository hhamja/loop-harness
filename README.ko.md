# loopy

[English](README.md) | **한국어**

[![License: MIT](https://img.shields.io/github/license/hhamja/loopy)](LICENSE)
[![Release](https://img.shields.io/github/v/release/hhamja/loopy)](https://github.com/hhamja/loopy/releases)

**에이전트는 "다 됐다"고 말합니다. 이 플러그인은 그걸 증명하게 만듭니다.**

loopy는 루프 엔지니어링을 위한 Claude Code 플러그인입니다: maker/checker 사이클을 돌리고, 기계 검증 가능한 rubric이 통과하기 전까지 "완료"를 인정하지 않습니다. 구현은 (가능하면) OpenAI Codex CLI에 위임하고, 채점은 독립된 읽기 전용 Claude verifier가 수행합니다 — 코드를 쓴 모델이 절대 그 코드를 채점하지 않는 교차 모델 분리입니다. 디스크 기반 상태는 세션이 죽어도 살아남습니다.

설계 불변식: **플러그인은 불변 로직**(머신당 1회 설치); **모든 가변 상태는 `.claude/loop/`에 존재**(`loop-init`이 프로젝트당 1회 생성).

## 설치

**경로 1 — marketplace:**

```
/plugin marketplace add <이-저장소-URL-또는-로컬-경로>
/plugin install loopy@loopy-marketplace
```

이 저장소는 `.claude-plugin/marketplace.json`을 포함하므로, 저장소 자체를 marketplace로 바로 추가할 수 있습니다 — 별도의 marketplace 저장소가 필요 없습니다.

**경로 2 — 로컬 개발:**

```
claude --plugin-dir /absolute/path/to/loopy
```

(절대 경로 권장.)

## 퀵스타트 (3분)

1. 프로젝트 디렉터리로 `cd`한 뒤 Claude Code를 시작합니다.
2. `/loopy:loop-init` 실행 — `.claude/loop/`(goal, rubric, state, memory, review, config)를 스캐폴딩하고, 테스트/린트/빌드 명령을 자동 감지하며, Codex CLI 사용 가능 여부를 감지합니다(`implementer:`를 그에 맞게 설정).
3. `.claude/loop/goal.md`와 `rubric.md`를 편집합니다 — 모든 기준에는 검증 명령이 필요합니다(loop-engineering 스킬의 rubric 가이드 참고).
4. `/loopy:loop-run` 실행 — rubric이 통과하거나 안전 장치가 발동할 때까지 구현(Codex 또는 Claude) → 검증을 반복합니다.
5. `/loopy:loop-status`는 언제든 실행해 진행 상황을 확인할 수 있으며, 항상 읽기 전용입니다.

## 점진적 도입

첫날부터 전체 루프를 돌릴 필요는 없습니다:

1. `/loopy:loop-run --verify-only` — 기존 코드를 rubric 기준으로 채점합니다; 보고서만 출력하고 아무것도 쓰지 않습니다(읽기 전용 보장은 신선한 세션 기준; 알려진 한계 참고).
2. `/loopy:loop-run --once` — 정확히 한 번의 구현+검증 사이클 후 정지.
3. `/loopy:loop-run` — 전체 루프. 안전 장치 포함: `max_iterations` 상한(기본 10)과 동일 기준 3회 연속 실패 시 에스컬레이션.

## 기존 하네스 리뷰

`/loopy:loop-review [경로]`는 임의의 프로젝트의 에이전트/루프 하네스를 제어 평면(`docs/loop-control-plane.md`) 기준으로 리뷰합니다 — `.claude/loop/`가 없어도 됩니다. 메인 에이전트가 오케스트레이터로서 읽기 전용 리뷰어들을 팬아웃합니다 — ETCLOVG 7책임(Execution, Tooling, Context, Lifecycle, Observability, Verification, Governance)을 증거 인용과 성숙도 레벨(L0–L5)로 채점하는 `loop-architect`, 그리고 게이트 우회·승인 마커 위조·rubber-stamp를 적대적으로 파고드는 `design-critic` — 그다음 critic의 악용 가능한 발견을 직접 재현해 확인한 뒤, 시공 순서로 정렬된 우선 수정안과 함께 `harness-review.md`를 기록합니다. 초기화된 루프의 *프로세스*를 채점하는 `loop-audit`와 달리, 이쪽은 하네스 *아키텍처가 존재하는지와 게이트가 실제로 버티는지*를 리뷰합니다. `--fix`를 붙이면 한 걸음 더 갑니다: high-severity·기계검증 가능한 발견을 `review/…` 브랜치에서 `loop-run`으로 자율 수정하고 — 각 발견의 재현이 rubric의 `verify:` 커맨드가 되어 수정이 기계로 증명되고, 리뷰어가 자기 수정을 채점하지 않습니다 — draft PR에서 정지합니다(머지는 사람 게이트로 남음). 설계급 발견은 자동으로 짓지 않고 PR로 에스컬레이트합니다.

## 교차 모델 maker/checker (Codex)

구현 단계를 OpenAI Codex CLI에 위임할 수 있습니다 — 코드를 쓴 모델이 그 코드를 채점하는 일이 절대 없도록.

- **전제조건:** `codex` CLI 설치 + 인증(`codex login`). `loop-init`이 `codex --version`을 실행해 성공 시 `implementer: codex`, 아니면 `implementer: claude`로 설정합니다.
- **동작 방식:** 매 사이클마다 메인 에이전트가 `.claude/loop/` 디스크 상태(goal, 미해결 기준·검증 명령, 직전 verifier 실패 사유, distilled rules)에서 프롬프트를 새로 조립해 `codex exec --full-auto`를 fresh하게 1회 실행합니다 — resume 세션 재사용은 하지 않습니다. Codex의 전체 stdout은 `.claude/loop/.codex-log`로 가고, 메인 에이전트는 `.codex-last`(`--output-last-message`)만 읽으므로 Codex 출력이 Claude 컨텍스트를 채우지 않습니다. 프롬프트는 Codex가 `.claude/loop/`를 건드리거나 git commit/push하는 것을 금지합니다.
- **설정:** `loop.config.md`의 `implementer: codex | claude` + 선택적 `codex_args:` passthrough(예: `-m <model>`, 또는 네트워크 허용을 위한 `-c sandbox_workspace_write.network_access=true` — workspace-write 샌드박스는 기본적으로 네트워크를 차단합니다).
- **폴백:** run 시작 시 `codex --version`이 실패하면 이번 run 전체를 Claude로 진행하고 `state.md`/`memory.md`에 기록합니다. `codex exec` 호출이 비정상 종료하면 1회 재시도 후 해당 사이클만 Claude로 폴백합니다. `implementer: claude`로 두면 0.2.0 이전 동작 — Codex 의존성 전무 — 이 됩니다.

## 토큰 비용

루프, verifier, 서브에이전트는 토큰을 소비합니다 — 항상 작업 대비 비용을 따져보세요:

- verifier는 사이클당 1회(phase gate) 실행되며, 파일 편집마다 실행되지 않습니다.
- `explorer` 스카우트는 haiku로 실행됩니다(저렴); 광범위한 파일 읽기 대신 이것을 사용하세요.
- 각 run의 토큰 수치는 stop gate가 `.claude/loop/.last-usage`에 추정 기록하고(트랜스크립트 크기 휴리스틱 — 추정치일 뿐, 청구 데이터가 아님) `state.md` / `loop-status`에 표시됩니다.
- `implementer: codex`일 때 Codex 출력은 Claude 컨텍스트 밖에 유지되며, Codex 측 사용량은 OpenAI가 과금합니다 — `.last-usage` 추정치에 **포함되지 않습니다**.
- 전체 루프가 가치 있을지 확신이 없다면 `--verify-only`나 `--once`로 시작하세요.

## 경계 원칙

1. **"완료"는 주장이지 증명이 아닙니다** — 최종 검증은 사람의 몫입니다.
2. **이해 부채는 실재합니다** — 매 사이클마다 `.claude/loop/review.md`를 사람이 읽을 수 있는 요약(변경 파일, 핵심 변경, 리스크)으로 덮어씁니다. 꼭 읽으세요.
3. **루프, verifier, 서브에이전트는 토큰을 태웁니다** — 항상 비용/효익 판단의 대상이며, 기본값이 아닙니다.

## `.claude/loop/` 커밋 정책

숨김 임시 파일을 제외하고 전부 커밋하세요. `loop-init`이 `.gitignore`에 `.claude/loop/.*`를 추가합니다(`.run-marker`, `.last-usage`, `.last-push`, `.hook-debug.log`, 그리고 Codex I/O 파일 `.codex-prompt`, `.codex-last`, `.codex-log`를 커버); 보이는 파일들 — goal, rubric, state, memory, review, config — 은 팀 공유와 세션 복구를 위해 커밋하도록 설계되었습니다.

## 알려진 한계

- 전용 Grep/Glob 도구가 없는 Claude Code 버전(v2.1.201에서 관측): verifier와 explorer는 읽기 전용 Bash 동등물(`grep`/`find`)로 폴백합니다. verifier는 쓰기에 대해 hook으로 계속 보호되지만, explorer의 읽기 전용 속성은 프롬프트로만 강제됩니다.
- `claude --resume` 세션에서는 session id가 바뀌므로 해당 세션에서 Stop gate가 비활성일 수 있습니다(fail-open — 이 경우 잘못 차단하는 일은 없습니다).
- loop-run이 `state.md`를 갱신하기 전에 죽으면, 같은 세션의 다음 턴 종료가 1회 차단됩니다; gate가 요구하는 한 줄을 append하면 영구히 해소됩니다. 그 턴이 하필 `--verify-only`라면, 이 한 줄이 읽기 전용 보장의 유일한 예외입니다(보장 대상은 지속적인 커밋 대상 파일이며, 숨김 임시 파일 `.last-usage`는 범위 밖으로 동일 세션 marker가 존재하면 갱신됩니다).
- `implementer: codex`일 때 Codex는 network가 기본 **차단**된 workspace-write 샌드박스에서 실행됩니다; 의존성 설치가 필요한 goal은 `codex_args`로 네트워크를 허용(`-c sandbox_workspace_write.network_access=true`)하지 않으면 실패합니다.
- 대화형 세션에서는 첫 `codex exec` Bash 호출이 일반 권한 프롬프트를 띄웁니다; headless 실행은 이를 허용하는 permission mode가 필요합니다(설치됐지만 미인증인 Codex는 버전 체크는 통과하나 `codex exec`에서 실패해 Claude로 폴백됩니다).

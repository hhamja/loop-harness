# 엘리트 루프 엔지니어링 — 5명이 100명 몫을 하는 설계·아키텍처

> **이 문서의 용도.** 상위 1% 실리콘밸리 팀이 에이전트 루프로 극단적 레버리지를 내는 방식을, 에이전트가 읽고 **그대로 운영하도록** 정리한 규칙집이다. 보고서가 아니다. 작업을 시작하기 전에 읽고, 아래 흐름·게이트·휴리스틱대로 움직여라. 장황한 서술 금지, 규칙만.
>
> 범용 방법론이자 이 리포(`loop-harness`)에 매핑된다. 각 레이어의 마지막 열이 이 플러그인의 대응 조각이다.

---

## 1. 핵심 명제

- **레버리지는 코드를 빨리 쓰는 데서 오지 않는다. *일을 생산하는 시스템을 설계*하는 데서 온다.** 사람이 만드는 것은 코드가 아니라, 코드를 만들어내는 루프다.
- **역할 분리.** 사람 = 아키텍트 + 리뷰어 + 게이트. 에이전트 = scout(탐색) / maker(구현) / checker(검증).
- **병목은 이제 "작성"이 아니라 "검증"이다.** 위험이 쓰기에서 리뷰로 이동했다. 리뷰 처리량이 곧 팀 처리량이다.
- **하지 말 것 vs 할 것.** 에이전트를 더 빨리 타이핑하는 나로 쓰지 마라. 병렬로 돌리고, 기계로 채점하고, 디스크에 상태를 남기는 *시스템*으로 써라.

---

## 2. 레버리지 6원칙 — 20배는 어디서 오는가

| # | 원칙 | 왜 레버리지가 되나 | 근거 |
|---|------|-------------------|------|
| 1 | **설계 우선** | 모호한 프롬프트는 모델이 수천 개의 미명시 요구를 추측하게 만든다. LLM은 패턴 완성이지 독심술이 아니다. 스펙이 의도를 앞단에서 고정하면 재작업이 붕괴한다. | Spec Kit |
| 2 | **maker ≠ checker** | 같은 모델이 만들고 채점하면 self-preference bias로 **점수만 오르고 품질은 안 오른다.** 만든 쪽과 채점하는 쪽을 분리하라. | Agent-as-a-Judge |
| 3 | **기계검증 가능한 "done"** | "correct"를 결정 함수로 표현 못 하면 아직 만들 준비가 안 된 것이다. done은 주장이 아니라 통과하는 커맨드다. | eval-driven |
| 4 | **병렬 팬아웃 → 수렴** | 병렬 컨텍스트 = 단일 에이전트가 담을 수 없는 총 추론·토큰 용량. Anthropic 멀티에이전트가 단일 대비 **+90.2%**, 토큰량만으로 성능 분산의 ~80%가 설명됐다. | Anthropic 멀티에이전트 |
| 5 | **디스크 상태** | 컨텍스트는 유한하고 휘발한다(context rot). 진실은 파일에 두고, 각 출력은 "제안된 변경"으로 다뤄라. 그래야 리셋을 넘어 장기 작업이 유지된다. | context engineering |
| 6 | **블라스트 반경 비례 투자** | 사소·가역 작업은 자동으로 흘리고, 큰·비가역 작업에만 감독을 건다. 건강한 믹스 ≈ 80% 자동 / 15% 리뷰 / 5% 차단. 과잉 확인은 레버리지를 태운다. | 티어 게이트 |

---

## 3. 7 레이어 — 거시 아키텍처

작업은 아래 7층을 순서대로 통과한다. **각 층은 산출물이 있고, 소유자가 있고, 기계 체크가 있다.** 마지막 열이 `loop-harness` 대응이다.

| # | 레이어 | 산출물 | 소유자 | 기계 체크 | loop-harness |
|---|--------|--------|--------|-----------|--------------|
| 1 | 의도 / 스펙 | 목표 1문장 + 수용 기준 | 사람 | 기준 파일 존재 | ✅ `goal.md` + `rubric.md` |
| 2 | **설계 / 아키텍처** | `design.md` (컴포넌트·경계·데이터 흐름·대안 2~3·선택 근거) | 사람 + scout | 필수 섹션 채움 + 비평 통과 | ❌ **갭 — 없음** |
| 3 | **분해** | 순서·의존 있는 검증가능 작업(tasks) | 사람 + 에이전트 | 각 작업에 성공 조건 | ❌ **갭 — rubric이 평면적** |
| 4 | 구현 | 코드 (최소 변경) | maker (Codex/Claude) | 빌드/타입 통과 | ✅ `loop-run` implement |
| 5 | 검증 | 채점 리포트 | checker (verifier) | rubric의 `verify:` 커맨드 | ✅ `verifier` 에이전트 |
| 6 | 거버넌스 / 게이트 | 승인 기록 | 사람 (게이트) | T2 차단 훅 | ✅ decision gates |
| 7 | 감사 / 회고 | 프로세스 점검 + 축적된 규칙 | auditor | A1–A6 체크 | ✅ `auditor` + `memory.md` |

**진단.** 1·4·5·6·7은 이미 강하다. **비어 있는 건 딱 2(설계)와 3(분해)다.** 그래서 "설계 먼저"가 매번 안 되는 것은 느낌이 아니라 구조다 — 루프가 rubric만 있으면 곧장 구현으로 뛴다. 여기가 다음 작업의 표적이다.

---

## 4. 작업 흐름 — operating rhythm

한 작업의 라이프사이클. 각 단계: **입력 → 행동 → 산출 → 다음 게이트.** (Spec Kit `specify→plan→tasks→implement`, Kiro `requirements→design→tasks`를 일반화.)

```
스코프        요구·제약 파악 → 목표 1문장 + 수용 기준             → goal/rubric
   ↓
설계          접근법 2~3안 비교 → 경계·인터페이스·트레이드오프    → design.md
   ↓          → 별도 비평 에이전트가 적대적 리뷰(maker≠checker)
 [설계 게이트]  큰/비가역 작업이면 사람 승인. 사소/가역이면 통과.
   ↓
분해          설계를 순서·의존 있는 작업으로. 각 작업에 성공 조건.  → tasks
   ↓
구현(병렬)     독립 작업은 팬아웃. maker가 작업당 최소 변경.        → 코드
   ↓
검증          checker가 rubric의 verify 커맨드로 채점. 자기채점 X.  → 리포트
   ↓
 [사람 게이트]  머지·릴리스·비가역 액션에만 사람. push까지는 자동.
   ↓
감사/기억      프로세스 점검 + 실패에서 규칙 distill → 디스크.       → audit/memory
```

**게이트 경계는 push가 아니라 merge/release 선이다.** 코드 쓰기·테스트·로컬 커밋·작업 브랜치 push·draft PR은 자동(T0). 머지·릴리스·태그·publish·force-push만 사람(T2).

---

## 5. 결정 휴리스틱 — When X → do Y

에이전트가 즉시 적용하는 규칙. 애매하면 이 표가 우선한다.

| 상황 (X) | 행동 (Y) |
|----------|----------|
| 요구가 모호하다 | 코딩 중단. 스펙/질문 먼저. 추측으로 짜지 마라. |
| 변경이 여러 파일에 걸치거나 새 서브시스템이다 | `design.md` 먼저 + 설계 게이트. 바로 코드 금지. |
| "done"을 커맨드로 표현할 수 없다 | 아직 만들 준비 안 됨. 먼저 rubric(검증가능 기준)부터. |
| 독립 작업이 3개 이상 | 병렬 에이전트로 팬아웃 → 결과 dedup → 수렴. |
| 리서치/탐색 복잡도 | 서브에이전트 규모를 스케일: 단순 사실=1, 비교=2~4, 복잡=10+. |
| 액션이 가역·로컬 | 자동 실행, **재확인 금지** (T0). |
| 액션이 공유·관측가능하나 가역 | 실행하되 `review.md`에 기록 (T1). |
| 액션이 비가역 또는 고임팩트 | 멈추고 사람 게이트 (T2). 우회 금지. |
| 같은 실패를 2~3회 반복 | 동일 재시도 금지. 에스컬레이트하거나 접근을 바꿔라. |
| 컨텍스트 한계에 근접 | 상태를 디스크에 압축 기록 후 리셋. 채팅 히스토리를 기억으로 쓰지 마라. |
| 멀티에이전트를 쓸까 | 작업 가치가 ~15배 토큰 비용을 정당화할 때만. 코딩은 리서치보다 병렬화 가능 하위작업이 적다. |

---

## 6. 안티패턴 — 레버리지를 죽이는 것

- **코드로 직행** (설계·스펙 스킵) → 나쁜 신호로 행동하고 이해 부채가 폭증한다. 설계 게이트로 막아라.
- **자기 채점** → 만든 모델이 채점하면 편향으로 점수가 뜬다. maker≠checker.
- **무한 루프** → 외부 체크 없는 모델은 자기 자신과 원을 그리며 동의한다. iteration cap + 정지 조건 필수.
- **컨텍스트 = 기억** (state rot) → 히스토리에만 있는 상태는 재도출되며 드리프트한다. 구조화된 디스크 상태, 출력은 "제안된 변경".
- **과잉 스폰 / 과잉 확인** → 사소 쿼리에 50개 서브에이전트를 띄우거나, 가역 작업마다 재확인해 멈춘다. 규모를 스케일하고 중복 호출을 가드하라.
- **미검토 PR 제출** → 본인이 안 본 PR을 올리는 건 일을 팀에 떠넘기는 것이다. 레버리지가 상쇄된다.
- **툴/컨텍스트 비대** → 모호한 결정점이 많은 툴셋, 하드코딩된 프롬프트 분기, 욱여넣은 예시는 전부 성능을 떨어뜨린다.
- **잘못된 도메인 병렬화** → 실시간 조율이 필요한 작업엔 멀티에이전트가 안 맞는다. 병렬화 이득이 분명할 때만.

---

## 7. 5인 팀 매핑 — 누가 무엇을 소유하나

레버리지의 핵심은 **소수의 사람이 다수의 에이전트 프로세스를 지휘**하는 것이다. 예전 대규모 팀이 몇 달 걸리던 일을 소수 팀이 해낸다 — **단, 병목은 검증이므로 리뷰 역량이 곧 처리량이다.**

| 사람이 소유 (위임 불가) | 에이전트에 위임 |
|------------------------|-----------------|
| 아키텍처·트레이드오프 결정 | 코드베이스 탐색 (scout) |
| 스펙·수용 기준 정의 | 구현 — 작업당 최소 변경 (maker) |
| 최종 리뷰·판단·taste | rubric 대비 채점 (checker) |
| T2 게이트 승인 (머지·릴리스) | 반복·재시도 (cap 안에서) |
| 감사·회고, 규칙 distill | 병렬 팬아웃 실행 |

> 원칙: **"필요보다 많은 감독으로 시작해, 데이터가 말할 때 줄여라."** 자동 승인 범위는 캘린더가 아니라 측정된 성과가 정당화할 때 넓힌다.

---

## 8. 근거 / 출처

- **Anthropic — Building a multi-agent research system** · https://www.anthropic.com/engineering/multi-agent-research-system — orchestrator-worker 팬아웃, 서브에이전트 규모 규칙, +90.2%, ~15배 토큰비용, 과잉 스폰.
- **Anthropic — Effective context engineering for AI agents** · https://www.anthropic.com/engineering/effective-context-engineering-for-ai-agents — 컨텍스트는 유한 자원, context rot, 디스크 노트/메모리, 서브에이전트 격리+압축 반환, 툴/프롬프트 비대.
- **GitHub — Spec-driven development (Spec Kit)** · https://github.blog/ai-and-ml/generative-ai/spec-driven-development-with-ai-get-started-with-a-new-open-source-toolkit/ · https://github.com/github/spec-kit — specify→plan→tasks→implement, "패턴 완성이지 독심술 아님", 스펙=단일 진실원.
- **AWS Kiro — Specs** · https://kiro.dev/docs/specs/ — requirements/design/tasks 3단계, 의존 "waves", 수용 기준을 강제 제약으로.
- **eval-driven.org** · https://evaldriven.org/ — 기계검증 done, eval = dataset+grader+harness를 코드 전에, "correct를 결정함수로 못 쓰면 만들 준비 안 됨".
- **Agent-as-a-Judge (survey)** · https://arxiv.org/html/2508.02994v1 — self-preference bias, 생성자가 스스로 채점 못 하는 이유, 분리 검증자·다중판정·적대적 구조·투표.
- **AI agent human-approval guardrails** · https://www.betterclaw.io/blog/ai-agent-human-approval-guardrails — 가역성+블라스트 반경 티어(T1/T2/T3), 80/15/5 믹스, "감독 많게 시작해 데이터가 말할 때 줄여라".
- **Task decomposition for AI agents** · https://brightlume.ai/blog/task-decomposition-ai-agents-break-down-work — 좋은 하위작업(specific·achievable·ordered·measurable), 평면 리스트가 실패하는 이유, 계층적 분해의 병렬화·복구 이득.
- **Addy Osmani — The future of agentic coding** · https://addyosmani.com/blog/future-agentic-coding/ — 사람의 altitude 이동(implementer→orchestrator), 소수 팀의 대규모 레버리지, 모호 스펙·리뷰 스킵 안티패턴.
- **Simon Willison — Agentic engineering anti-patterns** · https://simonwillison.net/guides/agentic-engineering-patterns/anti-patterns/ — 미검토 에이전트 PR을 올리지 마라.

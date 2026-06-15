# com.ragwatson — 모노레포 LLM 지침 (루트)

Karpathy-style **Harness Engineering** + **Wiki/PKS** 모노레포의 최상위 지침이다.  
도메인·스택별 상세는 **아래 링크 문서**를 따른다. 본문과 충돌 시 **`vault/DEVOPS/*` > 하위 `CLAUDE.md` > 본 문서** 순으로 적용한다.

**트레이드오프:** 속도보다 신중함. 사소한 작업은 상황에 맞게 판단한다.

---

## 문서 계층 (4단)

| 범위 | `.cursorrules` | `CLAUDE.md` |
|------|----------------|-------------|
| **모노레포 루트** | [.cursorrules](./.cursorrules) | **본 문서** |
| **백엔드** `eungsang/` | [eungsang/.cursorrules](./eungsang/.cursorrules) | [eungsang/CLAUDE.md](./eungsang/CLAUDE.md) |
| **프론트** `jebbi/` | [jebbi/.cursorrules](./jebbi/.cursorrules) | [jebbi/CLAUDE.md](./jebbi/CLAUDE.md) |
| **백엔드 앱** (예: titanic) | [eungsang/apps/titanic/_docs/.cursorrules](./eungsang/apps/titanic/_docs/.cursorrules) | [eungsang/apps/titanic/_docs/CLAUDE.md](./eungsang/apps/titanic/_docs/CLAUDE.md) |
| **Obsidian 그래프** | — | [GRAPH.md](./GRAPH.md) (경로별 색상 범례·허브 링크) |

- 백엔드 도메인 앱(`photo_battle`, `secom`, …)은 **titanic과 동일한 시블링 패턴**: `eungsang/apps/{app}/_docs/.cursorrules` + `CLAUDE.md`를 추가한다.
- 코딩 규칙 인덱스: [vault/README.md](./vault/README.md) (서브모듈 `vault`, 구 `docs`)

---

## Project Overview

- **목표:** 개인·도메인 지식을 원자 단위로 분해하고, LLM 컨텍스트에 효율적으로 연결하는 구조화 지식 시스템.
- **저장소 구성**
  - `eungsang/` — FastAPI 백엔드 (서브모듈)
  - `jebbi/` — Next.js 프론트 (서브모듈)
  - `vault/` — DEVOPS·ERD·Wiki 문서 (서브모듈)
  - `Docker-compose.yaml` — 로컬 `eungsang-api` + `eungsang-web`

---

## 1. 구현 전 사고 (Think Before Coding)

**가정하지 말 것. 혼란을 숨기지 말 것. 트레이드오프를 드러낼 것.**

- 가정은 명시한다. 불확실하면 질문한다.
- 해석이 여러 가지면, 조용히 하나를 고르지 말고 대안을 제시한다.
- 더 단순한 방법이 있으면 말한다. 타당하면 사용자 요청에도 반박한다.
- 불명확하면 멈춘다. 무엇이 헷갈리는지 짚고 질문한다.

---

## 2. 단순성 우선 (Simplicity First)

**문제를 푸는 데 필요한 최소한의 코드만. 추측성 코드는 없다.**

- 요청 범위를 넘는 기능·설정·추상화를 넣지 않는다.
- 일회성 코드를 위한 추상화는 만들지 않는다.
- 현실적으로 일어날 수 없는 시나리오를 위한 예외 처리는 하지 않는다.
- 200줄로 쓸 일을 50줄로 줄일 수 있으면 다시 쓴다.

---

## 3. 정밀한 수정 (Surgical Changes)

**꼭 필요한 곳만 건드린다. 정리는 자기가 만든 잔여물만 한다.**

- 인접 코드·주석·포맷을 “개선”하려 들지 않는다.
- 망가지지 않은 코드는 리팩터링하지 않는다. 기존 스타일을 유지한다.
- 무관한 데드 코드는 **언급만** 하고, 임의로 지우지 않는다.
- **내 변경**으로 불필요해진 import·변수·함수만 제거한다.

**검증:** diff의 모든 변경은 사용자 요청과 직접 연결되어야 한다.

---

## 4. 목표 중심 실행 (Goal-Driven Execution)

**성공 기준을 정의한다. 검증될 때까지 반복한다.**

- “유효성 검사 추가” → 잘못된 입력 테스트 작성 후 통과
- “버그 수정” → 재현 테스트 작성 후 통과
- 여러 단계일 때: `단계 → 검증` 형태의 짧은 계획을 먼저 쓴다.

---

## Karpathy Harness Engineering (공통)

- 지식을 **원자 단위**로 분해한다.
- **계층적 파일**(Wiki 스타일)로 구조화한다.
- **identity · rules · boundary**를 상위 도메인으로 유지한다.
- 에이전트 하네스 요약: [AGENTS.md](./AGENTS.md) · Cursor 실천: [CURSOR.md](./CURSOR.md)

---

## 작업 시 읽을 문서 (권장 `@` 멘션)

```text
# 공통
@AGENTS.md
@CLAUDE.md

# 백엔드
@eungsang/.cursorrules
@eungsang/CLAUDE.md
@vault/DEVOPS/Backend/BACKEND_RULES.md

# 프론트
@jebbi/.cursorrules
@jebbi/CLAUDE.md
@vault/DEVOPS/Frontend/REACT_RULES.md

# 타이타닉 앱
@eungsang/apps/titanic/_docs/.cursorrules
@eungsang/apps/titanic/_docs/CLAUDE.md
```

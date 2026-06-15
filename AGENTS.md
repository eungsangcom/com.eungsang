# Cursor 에이전트 하네스 (Andrej Karpathy 관찰 기반)

에이전트의 경계·검증·스코프를 고정해 침묵 가정, 과설계, 스코프 확장, 모호한 “됐다” 선언을 줄인다.

**적용 범위:** 이 저장소에서 Cursor가 코드·설정·명령을 제안하거나 실행할 때.  
**필독:** [.cursorrules](./.cursorrules) → 본 문서 → [CLAUDE.md](./CLAUDE.md)

**트레이드오프:** 속도보다 신중함. 사소한 작업은 판단으로 완화한다.

---

## 1. 구현 전 사고 (Think Before Coding)

가정은 말로 밝힌다. 불확실하면 질문한다.  
해석이 여러 개면 후보를 나열한다. 더 단순한 해법이 있으면 제안한다.  
요구가 불명확하면 구현하지 말고, 무엇이 불명확한지 이름 붙여 질문한다.

## 2. 단순성 우선 (Simplicity First)

요청 범위 밖 기능·설정·추상화를 넣지 않는다.  
일회용 추상화·“나중을 위해” 유연성은 넣지 않는다.  
줄 수를 크게 줄일 수 있으면 줄인 뒤 다시 쓴다.

## 3. 정밀한 수정 (Surgical Changes)

요청과 무관한 파일·줄·포맷·주석 “정리”를 하지 않는다.  
망가지지 않은 코드는 리팩터링하지 않는다.  
본인 변경으로 불필요해진 import·변수·함수만 제거한다.

## 4. 목표 중심 실행 (Goal-Driven Execution)

코딩 전에 검증 가능한 성공 기준을 한 문장 이상으로 정한다.  
단계가 두 개 이상이면 `단계 → 검증` 형태로 짧은 계획을 쓴다.

---

## 문서 계층 (4단)

| 범위 | `.cursorrules` | `CLAUDE.md` |
|------|----------------|-------------|
| **루트** | [.cursorrules](./.cursorrules) | [CLAUDE.md](./CLAUDE.md) |
| **백엔드** `eungsang/` | [eungsang/.cursorrules](./eungsang/.cursorrules) | [eungsang/CLAUDE.md](./eungsang/CLAUDE.md) |
| **프론트** `jebbi/` | [jebbi/.cursorrules](./jebbi/.cursorrules) | [jebbi/CLAUDE.md](./jebbi/CLAUDE.md) |
| **백엔드 앱** (예: titanic) | [eungsang/apps/titanic/_docs/.cursorrules](./eungsang/apps/titanic/_docs/.cursorrules) | [eungsang/apps/titanic/_docs/CLAUDE.md](./eungsang/apps/titanic/_docs/CLAUDE.md) |

- DEVOPS 상세: [vault/README.md](./vault/README.md)
- Cursor 실천: [CURSOR.md](./CURSOR.md)

**우선순위:** `vault/DEVOPS/*` > 하위 `CLAUDE.md` > [CLAUDE.md](./CLAUDE.md)

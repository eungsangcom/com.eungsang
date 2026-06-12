# Cursor 하네스 가이드 (이 저장소)

이 문서는 **Cursor에서 에이전트/챗을 쓸 때의 하네스**를 설명한다. 모델 자체를 바꾸는 것이 아니라, **규칙·맥락·검증**으로 Andrej Karpathy가 정리한 실패 패턴(묵시적 가정, 과한 일반화, 무분별한 수정, 모호한 완료 기준)을 줄이는 **하네스 엔지니어링** 관점이다. 상세 행동 규범은 루트의 `CLAUDE.md`를 따른다.

**트레이드오프:** 속도보다 신중함. 사소한 작업은 판단으로 완화한다.

---

## 하네스에 포함되는 파일

| 파일 | 역할 |
|------|------|
| **루트** `.cursorrules` | Cursor 자동 주입 — `docs/` + `backend/cursorrules` 연결 |
| `backend/cursorrules` | 백엔드·공통 **하네스** + **`docs/` 필수 참조** |
| `backend/CLAUDE.md` | Karpathy 가이드라인 **전문** |
| **`docs/README.md`** | **코딩 규칙 인덱스** (DEVOPS 상세 문서 목록) |
| `docs/DEVOPS/Backend/BACKEND_RULES.md` | FastAPI·레이어·DB 규칙 |
| `docs/DEVOPS/Frontend/REACT_RULES.md` | React·state·FormData 규칙 |
| `CURSOR.md` | (본 문서) Cursor 실천 안내 |

충돌 시: **`docs/DEVOPS/*` (도메인 상세)** > `cursorrules` / `CLAUDE.md` (일반 하네스).

---

## 필수 워크플로: `docs/` 먼저

1. `@docs/README.md` 로 규칙 목록 확인  
2. 백엔드면 `@docs/DEVOPS/Backend/BACKEND_RULES.md`, 프론트면 `@docs/DEVOPS/Frontend/REACT_RULES.md`  
3. `@backend/cursorrules` 하네스(단순성·정밀 수정) 적용  
4. 그 다음 구현·diff

규칙 없이 코드만 쓰지 않는다.

---

## Karpathy 의도를 Cursor에 옮기기

1. **구현 전 사고:** `@`로 관련 파일·**docs 규칙**을 붙이고, 모호하면 코딩 전에 질문하게 한다.  
2. **단순성:** “부가 기능·설정·추상화”는 채팅 지시에 없으면 넣지 않는다.  
3. **정밀한 수정:** diff는 요청과 직접 연결되게; 인접 “정리” 리팩터링은 피한다.  
4. **목표 중심:** PR/커밋 전에 “어떤 명령·테스트로 끝났는지”를 스스로 기준으로 삼는다.

자세한 문장과 예시는 **`CLAUDE.md`**를 본문으로 사용한다.

---

## Cursor에서의 실천 (하네스 운용)

- **맥락:** 작업 범위에 맞는 파일·폴더·**docs/DEVOPS 규칙**을 대화에 포함한다.  
- **검증:** “돌아가게” 대신, 가능하면 테스트·빌드·린트 등 **재현 가능한 확인**을 한 번이라도 돌린 뒤 끝낸다.  
- **루프:** 계획 → **docs 확인** → 변경 → 확인 → 필요할 때만 추가 수정.  
- **규칙 변경:** 상세는 `docs/DEVOPS/`에 추가하고, `cursorrules`는 짧게 유지한다.

---

## 이 하네스가 잘 먹히는지

- `docs/`를 거친 뒤 도메인 규칙에 맞는 코드가 작성된다.
- 불필요한 diff와 되돌리기가 줄고, **구현 전** 질문·대안 제시가 늘어난다.

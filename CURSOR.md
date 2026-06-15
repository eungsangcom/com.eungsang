# Cursor 하네스 가이드 (이 저장소)

Cursor에서 에이전트/챗을 쓸 때의 **하네스 운용** 안내. 상세 행동 규범은 [CLAUDE.md](./CLAUDE.md)를 본문으로 사용한다.

---

## 문서 계층 (4단)

| 범위 | `.cursorrules` | `CLAUDE.md` |
|------|----------------|-------------|
| 루트 | [.cursorrules](./.cursorrules) | [CLAUDE.md](./CLAUDE.md) |
| 백엔드 `eungsang/` | [eungsang/.cursorrules](./eungsang/.cursorrules) | [eungsang/CLAUDE.md](./eungsang/CLAUDE.md) |
| 프론트 `jebbi/` | [jebbi/.cursorrules](./jebbi/.cursorrules) | [jebbi/CLAUDE.md](./jebbi/CLAUDE.md) |
| 백엔드 앱 (titanic 등) | `eungsang/apps/{app}/_docs/.cursorrules` | `eungsang/apps/{app}/_docs/CLAUDE.md` |

- 에이전트 요약: [AGENTS.md](./AGENTS.md)
- DEVOPS 인덱스: [vault/README.md](./vault/README.md)

**충돌 시:** `vault/DEVOPS/*` > 하위 `CLAUDE.md` > 루트 `CLAUDE.md`

---

## 필수 워크플로

1. 작업 범위에 맞는 `.cursorrules` + `CLAUDE.md` 확인  
2. [vault/README.md](./vault/README.md) → 해당 DEVOPS 문서  
3. 구현 → 검증 (테스트·빌드·린트)

```text
# 백엔드
@eungsang/.cursorrules @eungsang/CLAUDE.md @vault/DEVOPS/Backend/BACKEND_RULES.md

# 프론트
@jebbi/.cursorrules @jebbi/CLAUDE.md @vault/DEVOPS/Frontend/REACT_RULES.md

# titanic 앱
@eungsang/apps/titanic/_docs/CLAUDE.md
```

---

## Karpathy 의도 → Cursor 실천

1. **구현 전 사고** — `@`로 관련 파일·규칙을 붙이고, 모호하면 코딩 전 질문  
2. **단순성** — 채팅에 없는 부가 기능·추상화 금지  
3. **정밀한 수정** — diff는 요청과 직접 연결  
4. **목표 중심** — “어떤 명령·테스트로 끝났는지” 기준 명시

---

## 이 하네스가 잘 먹히는지

- 규칙 문서를 거친 뒤 도메인에 맞는 코드가 작성된다.  
- 불필요한 diff가 줄고, **구현 전** 질문·대안 제시가 늘어난다.

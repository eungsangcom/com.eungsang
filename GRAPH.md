# 그래프 색상 맵 (Obsidian)

그래프 뷰 **설정 → 그룹** 에서 경로별 색상이 적용된다.  
Obsidian에서 그래프를 다시 열거나 `Cmd+R`로 새로고침하면 반영된다.

## 색상 범례

| 색 | 범위 | 쿼리 |
|----|------|------|
| 🟠 주황 | 타이타닉 앱 | `path:apps/titanic` |
| 🟢 청록 | Photo Battle 앱 | `path:photo_battle` |
| 🔵 파랑 | 백엔드 DEVOPS | `path:DEVOPS/Backend` |
| 🟢 초록 | 프론트 DEVOPS | `path:DEVOPS/Frontend` |
| 🔵 하늘 | `eungsang/` 백엔드 | `path:eungsang` |
| 🟢 민트 | `jebbi/` 프론트 | `path:jebbi` |
| 🟣 보라 | `vault/` 문서 | `path:vault` |
| 🔴 빨강 | `.cursorrules` 하네스 | `file:.cursorrules` |
| 🟡 금색 | 루트 하네스 (`AGENTS`, `CURSOR`, `CLAUDE`) | 루트 전용 쿼리 |
| ⚫ 회색 | `_harness/` | `path:_harness` |
| ⚪ 슬레이트 | `Docker-compose` | `file:Docker-compose` |

## 문서 허브 (그래프 연결)

- [[CLAUDE|루트 CLAUDE]]
- [[AGENTS]]
- [[CURSOR]]
- [[eungsang/CLAUDE|eungsang CLAUDE]]
- [[jebbi/CLAUDE|jebbi CLAUDE]]
- [[eungsang/apps/titanic/_docs/claude|titanic CLAUDE]]
- [[vault/README|vault README]]
- [[vault/DEVOPS/README|DEVOPS 인덱스]]
- [[vault/DEVOPS/Backend/BACKEND_RULES|BACKEND_RULES]]
- [[vault/DEVOPS/Frontend/REACT_RULES|REACT_RULES]]

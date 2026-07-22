# SigLIP 임베딩·채점 서버 (윈도우 GPU)

`google/siglip-so400m-patch14-384`로 이미지/텍스트 임베딩과 포토배틀 미학 점수를 제공한다.
맥미니 backend는 `SIGLIP_URL`로 이 서버를 호출한다.

| 포트 | 서비스 |
|------|--------|
| 8420 | KURE 텍스트 임베딩 |
| 8426 | ArtiMuse 심사 |
| 8427 | mac_git_sync (맥북 전용, SigLIP 아님) |
| **8437** | **SigLIP** (윈도우·맥북 공통) |

## API

- `GET /health`
- `POST /embed/texts` `{ "texts": ["..."] }` → `{ embeddings, dim, model }`
- `POST /embed/image` multipart `file`
- `POST /score` multipart `file` → `{ overall: 0~100, breakdown }`
- `POST /rank` multipart `file` + `labels` (JSON array)

## 설치 (윈도우 GPU, 최초 1회)

```powershell
# CUDA torch (버전에 맞게)
pip install torch torchvision --index-url https://download.pytorch.org/whl/cu121

cd G:\project\com.eungsang\scripts\siglip_server
pip install -r requirements.txt

copy config.cmd.example config.cmd
# config.cmd 편집 후:
.\run_server.bat
```

첫 기동 시 HuggingFace에서 모델을 내려받는다 (~800MB+).

헬스 확인:

```powershell
curl http://127.0.0.1:8437/health
```

## 맥미니 backend `.env`

```env
SIGLIP_URL=http://100.x.x.x:8437
NIMA_URL=http://100.x.x.x:8437/nima
SIGLIP_TIMEOUT_SEC=120
```

포토배틀: `SIGLIP_URL`이 있으면 채점 체인에 포함(우선순위: NIMA → SigLIP → Gemini).
갤러리 검색: `POST /gallery/index`, `GET /gallery/search`.

백엔드가 `GALLERY_SIGLIP_AUTO_INDEX=1`(기본)이면 **10분마다** 미인덱싱 사진만 자동 인덱싱한다
(`GALLERY_SIGLIP_AUTO_INDEX_INTERVAL_SEC=600`).

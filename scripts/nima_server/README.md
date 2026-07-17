# NIMA 미학 심사 서버 (윈도우 GPU)

[NIMA (Neural Image Assessment)](https://arxiv.org/abs/1709.05424)로 사진을 0~100점 평가한다.
맥미니 backend가 `NIMA_URL`로 `POST /score`를 호출한다.

| 포트 | 서비스 |
|------|--------|
| 8420 | KURE 텍스트 임베딩 |
| 8426 | ArtiMuse 심사 |
| 8427 | SigLIP |
| **8428** | **NIMA** |

## API

- `GET /health`
- `POST /score` multipart `file` → `{ overall: 0~100, model, breakdown }`

## 설치 (윈도우 GPU, 최초 1회)

```powershell
# CUDA torch (버전에 맞게)
pip install torch torchvision --index-url https://download.pytorch.org/whl/cu121

cd G:\project\com.eungsang\scripts\nima_server
pip install -r requirements.txt

copy config.cmd.example config.cmd
# config.cmd 편집 후:
.\run_server.bat
```

첫 `/score` 시 PyIQA가 NIMA 가중치를 내려받는다.

헬스 확인:

```powershell
curl http://127.0.0.1:8428/health
```

## 맥미니 backend `.env`

```env
NIMA_URL=http://100.x.x.x:8428
NIMA_TIMEOUT_SEC=120
```

포토배틀 채점 우선순위: **NIMA → SigLIP → ArtiMuse → Gemini**.

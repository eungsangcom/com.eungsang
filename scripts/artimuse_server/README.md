# ArtiMuse 사진 심사 서버 (윈도우 GPU)

포토배틀 심사위원 AI. InternVL3-8B 기반 [ArtiMuse](https://huggingface.co/Thunderbolt215215/ArtiMuse)로
사진을 0~100점 + 8차원 전문 분석으로 평가한다. 맥미니 backend가 `POST /score`로 호출한다.

- CUDA GPU 필수 (16GB VRAM은 8-bit 양자화 권장, 기본값).
- 기존 Ollama/임베딩 서버와 GPU를 공유하므로 8-bit로 ~9~10GB만 사용.

## 1. 준비 (최초 1회)

```powershell
# 1) ArtiMuse 저장소 클론
git clone https://github.com/thunderbolt215/ArtiMuse.git C:\ai\ArtiMuse
cd C:\ai\ArtiMuse

# 2) torch (CUDA 버전에 맞게 — 예: cu121)
pip install torch torchvision --index-url https://download.pytorch.org/whl/cu121

# 3) ArtiMuse 모델 의존성
pip install -r requirements.txt

# 4) 체크포인트 다운로드 → checkpoints\ArtiMuse\
pip install "huggingface_hub[cli]"
huggingface-cli download Thunderbolt215215/ArtiMuse --local-dir checkpoints\ArtiMuse
```

## 2. 설정

```powershell
cd G:\project\com.eungsang\scripts\artimuse_server
copy config.ps1.example config.ps1
notepad config.ps1
```

`config.ps1` 예시:

```powershell
$env:PY = "C:\ProgramData\anaconda3\envs\artimuse\python.exe"
$env:ARTIMUSE_REPO = "C:\ai\ArtiMuse"
```

## 3. 실행 (수동 — VRAM ~10GB, 평소엔 끄기)

```powershell
cd G:\project\com.eungsang\scripts\artimuse_server
Set-ExecutionPolicy -Scope Process Bypass -Force
.\run_server.ps1
```

또는 conda에서 직접:

```powershell
conda activate artimuse
$env:ARTIMUSE_REPO = "C:\ai\ArtiMuse"
cd G:\project\com.eungsang
python scripts\artimuse_server\artimuse_server.py
```

```powershell
Invoke-WebRequest http://127.0.0.1:8426/health
```

방화벽 (관리자, 최초 1회): `.\open_firewall_port.ps1`

자동 기동(`install_task.ps1`)은 VRAM을 상시 점유하므로 **권장하지 않음**.

대신 **lazy load + idle unload**(기본값)를 쓰면:

- 서버 프로세스만 상시 실행 (포트 8426, RAM 수십 MB)
- **첫 `/score`(심사) 요청 시** GPU 모델 로드 (~15초)
- **마지막 심사 후 5분** (`ARTIMUSE_IDLE_UNLOAD_SEC=300`) 지나면 VRAM 자동 해제

`GET /health` → `model_loaded: false` 이면 VRAM은 비어 있는 상태.

## 4. 맥미니 backend 연결

`eungsang/.env` 에 다음을 추가하고 backend 재시작:

```
ARTIMUSE_URL=http://<윈도우 Tailscale IP>:8426
```

`ARTIMUSE_URL`이 설정되면 ArtiMuse 우선, 실패 시 Gemini로 자동 폴백한다.

## 환경변수 (config.cmd)

| 변수 | 기본값 | 설명 |
|------|--------|------|
| `ARTIMUSE_REPO` | (필수) | 클론한 ArtiMuse 저장소 경로 |
| `ARTIMUSE_MODEL_PATH` | `<repo>\checkpoints\ArtiMuse` | 체크포인트 폴더 |
| `ARTIMUSE_DEVICE` | `cuda:0` | 추론 디바이스 |
| `ARTIMUSE_LOAD_8BIT` | `1` | 8-bit 양자화 (16GB VRAM 권장) |
| `ARTIMUSE_USE_FLASH_ATTN` | `0` | flash-attn (윈도우 빌드 난해 → 기본 off) |
| `ARTIMUSE_INCLUDE_ANALYSIS` | `1` | 8차원 분석 포함 |
| `ARTIMUSE_MAX_NEW_TOKENS` | `512` | 분석 토큰 상한 |
| `ARTIMUSE_PORT` | `8426` | 서버 포트 |
| `ARTIMUSE_LAZY_LOAD` | `1` | 기동 시 모델 미로드, 심사 시 로드 |
| `ARTIMUSE_IDLE_UNLOAD_SEC` | `300` | 심사 후 VRAM 해제 대기(초), `0`=항상 상주 |

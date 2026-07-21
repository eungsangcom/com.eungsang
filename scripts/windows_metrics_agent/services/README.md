# GPU 서비스 (윈도우)

## 부팅 정책 (1회 설치, 관리자 PowerShell)

```powershell
cd G:\project\com.eungsang\scripts\windows_metrics_agent\services
Set-ExecutionPolicy -Scope Process Bypass
.\install_service_tasks.ps1
```

| 서비스 | 부팅 시 | 포트 |
|--------|---------|------|
| Ollama | **자동 ON** | 11434 |
| SigLIP | **자동 ON** | 8437 |
| NIMA | **자동 ON** | 8428 |
| 임베딩 (KURE) | 기본 OFF | 8420 |
| ArtiMuse | 기본 OFF | 8426 |

설비 담당 에이전트·맥미니 API로 원격 기동/중지: `ollama`, `siglip`, `nima`, `embedding`, `artimuse`, `all`

예: "임베딩 켜줘", "SigLIP 꺼줘"

---

## KURE 임베딩 (수동/원격)

## 1회 설정

```powershell
cd G:\project\com.eungsang\scripts\windows_metrics_agent

# conda base 활성화 확인 — 프롬프트에 (base) 표시
conda info --base          # 예: C:\ProgramData\anaconda3
Get-Command python         # Microsoft Store(WindowsApps) 아닌지 확인

# 의존성 설치 (5~10분, torch 포함) — (base) 에서 그대로 실행 가능
Set-ExecutionPolicy -Scope Process Bypass
.\services\install_kure_deps.ps1

# 스크립트 끝에 나온 PY= 줄을 config.cmd 에 저장 (메모장용 .cmd 파일, PowerShell set 아님)
copy config.cmd.example config.cmd
notepad config.cmd

# 작업 스케줄러 등록
cd services
.\install_service_tasks.ps1
```

## 수동 기동·확인

```powershell
Start-ScheduledTask -TaskName Eungsang-KureEmbed
# 1~3분 후
Invoke-WebRequest http://127.0.0.1:8420/health -UseBasicParsing
```

로그: `services\logs\kure_embed.log`

## 자주 나는 오류

| 증상 | 해결 |
|------|------|
| `pythoncore-3.14` 경로 | `config.cmd`에 conda `PY=` 설정 |
| `sentence_transformers` 없음 | `install_kure_deps.ps1` 실행 |
| 포트 8420 안 열림 | 로그에서 모델 다운로드·CUDA 오류 확인 |

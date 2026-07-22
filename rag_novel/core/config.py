from pydantic_settings import BaseSettings, SettingsConfigDict


class Settings(BaseSettings):
    model_config = SettingsConfigDict(env_file=".env", env_file_encoding="utf-8")

    db_dsn: str = "postgresql://eungsang:eung@192.168.0.72:5433/eungsang_DB"
    embed_url: str = "http://100.102.174.81:8420/embed"
    embed_model: str = "kure"
    ollama_host: str = "http://100.102.174.81:11434"
    novel_model: str = "qwen2.5:14b"
    top_k: int = 5


settings = Settings()

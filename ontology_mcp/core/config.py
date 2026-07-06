from pydantic_settings import BaseSettings, SettingsConfigDict

class Settings(BaseSettings):
    model_config = SettingsConfigDict(env_file=".env", env_file_encoding="utf-8")

    embed_url: str = "http://100.102.174.81:8420/embed"
    db_dsn: str = "postgresql://eungsang:eung@192.168.0.72:5433/eungsang_DB"
    default_model: str = "kure"
    default_namespace: str = "default"
    neo4j_uri: str = "bolt://localhost:7687"
    neo4j_user: str = "neo4j"
    neo4j_password: str = "neo4j"

settings = Settings()

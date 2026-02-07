"""Application configuration via environment variables."""

from pathlib import Path

from pydantic_settings import BaseSettings


class Settings(BaseSettings):
    """Igris service configuration.

    All values are overridable via environment variables prefixed with IGRIS_.
    """

    model_config = {"env_prefix": "IGRIS_"}

    # Server
    host: str = "0.0.0.0"
    port: int = 8920

    # Database
    db_path: str = "/data/igris.db"
    db_master_key_file: str = "/data/.igris-master-key"

    # Sessions
    session_ttl_seconds: int = 3600  # 1 hour default

    # Network security — comma-separated CIDR subnets
    allowed_subnets: str = "10.211.55.0/24,127.0.0.0/8"

    # FIDO2
    rp_id: str = "igris.local"
    rp_name: str = "Igris YubiKey Service"
    origin: str = "https://igris.local:8920"

    # Logging
    log_level: str = "INFO"

    @property
    def db_path_resolved(self) -> Path:
        return Path(self.db_path)

    @property
    def db_master_key_path(self) -> Path:
        return Path(self.db_master_key_file)

    @property
    def subnet_list(self) -> list[str]:
        return [s.strip() for s in self.allowed_subnets.split(",") if s.strip()]


settings = Settings()

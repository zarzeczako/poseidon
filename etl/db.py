"""Shared Neon connection helper -- reads POSEIDON_DATABASE_URL from .env."""

from __future__ import annotations

from pathlib import Path

import psycopg

_ENV_PATH = Path(__file__).parent.parent / ".env"


def load_dotenv_var(name: str, env_path: Path = _ENV_PATH) -> str:
    for line in env_path.read_text(encoding="utf-8").splitlines():
        line = line.strip()
        if line.startswith(f"{name}="):
            return line.split("=", 1)[1].strip()
    raise RuntimeError(f"{name} not found in {env_path}")


def connect() -> psycopg.Connection:
    return psycopg.connect(load_dotenv_var("POSEIDON_DATABASE_URL"))

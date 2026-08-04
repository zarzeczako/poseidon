"""Run a .sql file against the Neon database using POSEIDON_DATABASE_URL from .env."""

from __future__ import annotations

import sys
from pathlib import Path

import psycopg


def load_dotenv_var(name: str, env_path: Path) -> str:
    for line in env_path.read_text(encoding="utf-8").splitlines():
        line = line.strip()
        if line.startswith(f"{name}="):
            return line.split("=", 1)[1].strip()
    raise RuntimeError(f"{name} not found in {env_path}")


def main() -> None:
    if len(sys.argv) != 2:
        print("uzycie: python etl/run_sql_file.py sql/001_staging.sql")
        sys.exit(1)

    sql_path = Path(sys.argv[1])
    env_path = Path(__file__).parent.parent / ".env"
    database_url = load_dotenv_var("POSEIDON_DATABASE_URL", env_path)

    sql = sql_path.read_text(encoding="utf-8")
    with psycopg.connect(database_url, autocommit=True) as conn:
        with conn.cursor() as cur:
            cur.execute(sql)
    print(f"OK: {sql_path} wykonany bez bledow")


if __name__ == "__main__":
    main()

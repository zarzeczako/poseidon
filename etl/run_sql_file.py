"""Run a .sql file against the Neon database using POSEIDON_DATABASE_URL from .env."""

from __future__ import annotations

import sys
from pathlib import Path

from db import connect


def main() -> None:
    if len(sys.argv) != 2:
        print("uzycie: python etl/run_sql_file.py sql/001_staging.sql")
        sys.exit(1)

    sql_path = Path(sys.argv[1])
    sql = sql_path.read_text(encoding="utf-8")
    with connect() as conn:
        conn.autocommit = True
        with conn.cursor() as cur:
            cur.execute(sql)
    print(f"OK: {sql_path} wykonany bez bledow")


if __name__ == "__main__":
    main()

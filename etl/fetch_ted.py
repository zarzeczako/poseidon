"""Extract+Load: pobiera ogloszenia TED (Search API v3) i zapisuje surowo do
staging.ted_notices_raw. Query/fields to strukturalny wybor pol -- Python nie
podejmuje tu decyzji biznesowych, tylko przekazuje odpowiedz API 1:1 do payload.
"""

from __future__ import annotations

import sys
import time

import httpx
from psycopg.types.json import Json

from db import connect

SEARCH_URL = "https://api.ted.europa.eu/v3/notices/search"
SOURCE = "Search API v3"

FIELDS = [
    "publication-number",
    "publication-date",
    "notice-title",
    "notice-type",
    "form-type",
    "organisation-country-buyer",
    "organisation-identifier-buyer",
    "organisation-name-buyer",
    "tender-value",
    "tender-value-cur",
    "tender-value-highest",
    "tender-value-lowest",
    "winner-identifier",
    "winner-selection-status",
    "received-submissions-type-val",
    "received-submissions-type-code",
    # UWAGA (2026-08-04): "-cur-" to pole WALUTY ("PLN"), nie kwoty -- potwierdzone na
    # zywych danych (7 rekordow, wszystkie zwracaly wylacznie ['PLN']). Kwota jest w
    # osobnym polu bez "-cur-". TED ma szacunek na 4 poziomach granularnosci
    # (lot/part/proc/glo) -- ciagniemy wszystkie 4 + ich waluty, zeby na zywych danych
    # sprawdzic, ktory poziom sie faktycznie wypelnia, zamiast zgadywac.
    "estimated-value-lot",
    "estimated-value-cur-lot",
    "estimated-value-part",
    "estimated-value-cur-part",
    "estimated-value-proc",
    "estimated-value-cur-proc",
]


def search_page(client: httpx.Client, query: str, page: int, limit: int) -> dict:
    resp = client.post(
        SEARCH_URL,
        json={"query": query, "fields": FIELDS, "page": page, "limit": limit},
        timeout=30,
    )
    resp.raise_for_status()
    return resp.json()


def upsert_notice(conn, notice: dict) -> None:
    conn.execute(
        """
        INSERT INTO staging.ted_notices_raw (notice_id, source_file, payload)
        VALUES (%s, %s, %s)
        ON CONFLICT (notice_id) DO NOTHING
        """,
        (notice["publication-number"], SOURCE, Json(notice)),
    )


def main() -> None:
    query = sys.argv[1] if len(sys.argv) > 1 else "organisation-country-buyer=POL"
    max_pages = int(sys.argv[2]) if len(sys.argv) > 2 else 1
    page_limit = 20
    inserted = 0

    with httpx.Client() as client, connect() as conn:
        for page in range(1, max_pages + 1):
            result = search_page(client, query, page, page_limit)
            notices = result.get("notices", [])
            if not notices:
                print(f"strona {page}: pusto, koniec")
                break
            for n in notices:
                upsert_notice(conn, n)
                inserted += 1
            conn.commit()
            print(f"strona {page}: {len(notices)} ogloszen (razem: {inserted}, totalNoticeCount={result.get('totalNoticeCount')})")
            time.sleep(0.3)

    print(f"GOTOWE: {inserted} ogloszen w staging.ted_notices_raw")


if __name__ == "__main__":
    main()

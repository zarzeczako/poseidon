"""Extract+Load: pobiera ogloszenia BZP i zapisuje surowo do staging.bzp_notices_raw.

Uzywa Board/Search (prawdziwa paginacja PageNumber/PageSize) zamiast /notice (limit
500 rekordow na zapytanie, BEZ mozliwosci pobrania kolejnej strony -- potwierdzone na
zywych danych: jeden dzien TenderResultNotice juz przekracza 500). Board/Search nie
zwraca htmlBody, wiec dociagamy go osobno per-ogloszenie przez GetNoticeHtmlBodyById.
"""

from __future__ import annotations

import sys
import time

import httpx
from psycopg.types.json import Json

from db import connect

BASE = "https://ezamowienia.gov.pl/mo-board/api/v1"
SOURCE_ENDPOINT = "Board/Search+GetNoticeHtmlBodyById"


def search_page(client: httpx.Client, page_number: int, page_size: int) -> list[dict]:
    resp = client.get(
        f"{BASE}/Board/Search",
        params={
            "PageSize": page_size,
            "PageNumber": page_number,
            "SortingColumnName": "PublicationDate",
            "SortingDirection": "ASC",
        },
        timeout=30,
    )
    resp.raise_for_status()
    return resp.json()


def fetch_html_body(client: httpx.Client, object_id: str) -> str | None:
    # UWAGA: bez naglowka Accept -- z "Accept: application/json" ten endpoint owija
    # HTML w literal JSON-string (cudzyslowy i wewnetrzne cudzyslowy escapowane), a
    # resp.text bierze to surowo, zapisujac zle dane (znalezione i naprawione 2026-08-04).
    resp = client.get(
        f"{BASE}/Board/GetNoticeHtmlBodyById",
        params={"noticeId": object_id},
        headers={"Accept": "text/plain"},
        timeout=30,
    )
    if resp.status_code != 200:
        return None
    return resp.text


def upsert_notice(conn, notice: dict) -> None:
    conn.execute(
        """
        INSERT INTO staging.bzp_notices_raw (notice_id, source_endpoint, payload)
        VALUES (%s, %s, %s)
        ON CONFLICT (notice_id, source_endpoint) DO NOTHING
        """,
        (notice["noticeNumber"], SOURCE_ENDPOINT, Json(notice)),
    )


def main() -> None:
    page_size = 20
    max_pages = int(sys.argv[1]) if len(sys.argv) > 1 else 5
    inserted = 0

    with httpx.Client() as client, connect() as conn:
        for page in range(1, max_pages + 1):
            notices = search_page(client, page, page_size)
            if not notices:
                print(f"strona {page}: pusto, koniec")
                break
            for n in notices:
                html = fetch_html_body(client, n["objectId"])
                n["htmlBody"] = html
                upsert_notice(conn, n)
                inserted += 1
                time.sleep(0.2)  # uprzejmosc wobec serwera
            conn.commit()
            print(f"strona {page}: {len(notices)} ogloszen zapisanych (razem: {inserted})")

    print(f"GOTOWE: {inserted} ogloszen w staging.bzp_notices_raw")


if __name__ == "__main__":
    main()

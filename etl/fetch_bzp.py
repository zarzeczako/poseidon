"""Extract+Load: pobiera ogloszenia BZP i zapisuje surowo do staging.bzp_notices_raw.

Uzywa Board/Search (prawdziwa paginacja PageNumber/PageSize) zamiast /notice (limit
500 rekordow na zapytanie, BEZ mozliwosci pobrania kolejnej strony -- potwierdzone na
zywych danych). Board/Search stoi na Elasticsearchu z limitem 10 000 wynikow na
pojedyncze zapytanie (from+size) -- dlatego akwizycja tnie zakres dat na pojedyncze
dni (potwierdzone: nawet w szczycie ~2900-3000/dzien, daleko od 10k) i dla kazdego dnia
osobno paginuje az do wyczerpania. Board/Search nie zwraca htmlBody, wiec dociagamy go
osobno per-ogloszenie przez GetNoticeHtmlBodyById.
"""

from __future__ import annotations

import json
import sys
import time
from datetime import date, datetime, timedelta

import httpx
from psycopg.types.json import Json

from db import connect

BASE = "https://ezamowienia.gov.pl/mo-board/api/v1"
SOURCE_ENDPOINT = "Board/Search+GetNoticeHtmlBodyById"
SAFE_DAILY_LIMIT = 9000  # margines pod limitem Elasticsearcha (10 000)


def search_page(
    client: httpx.Client, page_number: int, page_size: int, date_from: str, date_to: str
) -> tuple[list[dict], int]:
    resp = client.get(
        f"{BASE}/Board/Search",
        params={
            "PageSize": page_size,
            "PageNumber": page_number,
            "SortingColumnName": "PublicationDate",
            "SortingDirection": "ASC",
            "PublicationDateFrom": date_from,
            "PublicationDateTo": date_to,
        },
        timeout=30,
    )
    resp.raise_for_status()
    pagination = json.loads(resp.headers.get("X-Pagination", "{}"))
    return resp.json(), pagination.get("TotalCount", 0)


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


def fetch_day(client: httpx.Client, conn, day: date, page_size: int = 500) -> int:
    day_str = day.isoformat()
    page = 1
    day_count = 0
    while True:
        notices, total_count = search_page(client, page, page_size, day_str, day_str)
        if page == 1 and total_count > SAFE_DAILY_LIMIT:
            print(f"  UWAGA: {day_str} ma {total_count} rekordow -- blisko limitu 10k Elasticsearcha, "
                  f"potrzebne dalsze cziecie (np. po godzinach)")
        if not notices:
            break
        for n in notices:
            n["htmlBody"] = fetch_html_body(client, n["objectId"])
            upsert_notice(conn, n)
            day_count += 1
            time.sleep(0.2)  # uprzejmosc wobec serwera
        conn.commit()
        if len(notices) < page_size:
            break
        page += 1
    return day_count


def fetch_range(client: httpx.Client, conn, date_from: date, date_to: date) -> int:
    total = 0
    day = date_from
    while day <= date_to:
        day_count = fetch_day(client, conn, day)
        total += day_count
        print(f"{day.isoformat()}: {day_count} ogloszen (razem: {total})")
        day += timedelta(days=1)
    return total


def main() -> None:
    if len(sys.argv) == 3:
        date_from = datetime.strptime(sys.argv[1], "%Y-%m-%d").date()
        date_to = datetime.strptime(sys.argv[2], "%Y-%m-%d").date()
    else:
        # domyslnie: pierwszy tydzien istnienia nowego BZP -- bezpieczny, maly test
        date_from, date_to = date(2021, 1, 2), date(2021, 1, 8)

    with httpx.Client() as client, connect() as conn:
        total = fetch_range(client, conn, date_from, date_to)

    print(f"GOTOWE: {total} ogloszen w staging.bzp_notices_raw (zakres {date_from} .. {date_to})")


if __name__ == "__main__":
    main()

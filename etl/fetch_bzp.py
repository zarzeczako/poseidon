"""Extract+Load: pobiera ogloszenia BZP i zapisuje surowo do staging.bzp_notices_raw.

Uzywa Board/Search (prawdziwa paginacja PageNumber/PageSize) zamiast /notice (limit
500 rekordow na zapytanie, BEZ mozliwosci pobrania kolejnej strony -- potwierdzone na
zywych danych). Board/Search stoi na Elasticsearchu z limitem 10 000 wynikow na
pojedyncze zapytanie (from+size) -- dlatego akwizycja tnie zakres dat na pojedyncze
dni (potwierdzone: nawet w szczycie ~2900-3000/dzien, daleko od 10k) i dla kazdego dnia
osobno paginuje az do wyczerpania. Board/Search nie zwraca htmlBody, wiec dociagamy go
osobno per-ogloszenie przez GetNoticeHtmlBodyById.

Zakres typow ograniczony do NOTICE_TYPES (patrz nizej) -- decyzja Architekta 2026-08-04
(sesja 2). Board/Search NIE laczy wielu wartosci NoticeType w jednym zapytaniu w OR
(potwierdzone empirycznie: powtorzony parametr po cichu bierze tylko pierwsza wartosc),
wiec kazdy typ to osobne zapytanie/osobna pelna paginacja per dzien.
"""

from __future__ import annotations

import json
import sys
import time
from datetime import date, datetime, timedelta

import httpx
from psycopg.types.json import Json

from db import connect
from parse_bzp_form import parse_bzp_html_body

BASE = "https://ezamowienia.gov.pl/mo-board/api/v1"
SOURCE_ENDPOINT = "Board/Search+GetNoticeHtmlBodyById"
SAFE_DAILY_LIMIT = 9000  # margines pod limitem Elasticsearcha (10 000)

# Zatwierdzone przez Architekta 2026-08-04 (sesja 2): tylko te dwa z 37 typow w
# glosariuszu -- ContractNotice niesie termin skladania ofert/tryb (F2), TenderResultNotice
# niesie liczbe ofert/ceny z SEKCJA VI (F1/F4). Reszta (w tym warianty ...EU) pomijana.
NOTICE_TYPES = ["ContractNotice", "TenderResultNotice"]


def search_page(
    client: httpx.Client,
    page_number: int,
    page_size: int,
    date_from: str,
    date_to: str,
    notice_type: str,
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
            "NoticeType": notice_type,
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


def upsert_notice(conn, notice: dict) -> int:
    # DO UPDATE (nie DO NOTHING) tylko po to, zeby RETURNING zadzialalo tez przy
    # konflikcie -- potrzebujemy bzp_row_id zawsze, nie tylko przy pierwszym zapisie,
    # bo od niego zalezy upsert_parsed_fields() nizej.
    row = conn.execute(
        """
        INSERT INTO staging.bzp_notices_raw (notice_id, source_endpoint, payload)
        VALUES (%s, %s, %s)
        ON CONFLICT (notice_id, source_endpoint) DO UPDATE SET payload = EXCLUDED.payload
        RETURNING id
        """,
        (notice["noticeNumber"], SOURCE_ENDPOINT, Json(notice)),
    ).fetchone()
    return row[0]


def upsert_parsed_fields(conn, bzp_row_id: int, parsed: dict) -> None:
    # Reprocesowalne z zalozenia (DO UPDATE): to pochodne dane (wynik parsera dzialajacego
    # na juz zapisanym htmlBody), nie surowa historia z API -- poprawiony parser ma prawo
    # nadpisac wczesniej wyekstrahowane wartosci tego samego pola.
    rows = [
        (bzp_row_id, None, code, v["etykieta"], v["wartosc"])
        for code, v in parsed["naglowek"].items()
    ]
    for czesc_nr, fields in parsed["czesci"].items():
        rows.extend(
            (bzp_row_id, czesc_nr, code, v["etykieta"], v["wartosc"])
            for code, v in fields.items()
        )
    if not rows:
        return
    conn.cursor().executemany(
        """
        INSERT INTO staging.bzp_form_parsed (bzp_row_id, czesc_nr, code, etykieta, wartosc)
        VALUES (%s, %s, %s, %s, %s)
        ON CONFLICT (bzp_row_id, czesc_nr, code)
        DO UPDATE SET etykieta = EXCLUDED.etykieta, wartosc = EXCLUDED.wartosc, parsed_at = now()
        """,
        rows,
    )


def is_day_done(conn, day: date, notice_type: str) -> bool:
    row = conn.execute(
        "SELECT 1 FROM staging.bzp_acquisition_log WHERE day = %s AND notice_type = %s",
        (day, notice_type),
    ).fetchone()
    return row is not None


def mark_day_done(conn, day: date, notice_type: str, count: int) -> None:
    conn.execute(
        """
        INSERT INTO staging.bzp_acquisition_log (day, notice_type, fetched_count)
        VALUES (%s, %s, %s)
        ON CONFLICT (day, notice_type)
        DO UPDATE SET fetched_count = EXCLUDED.fetched_count, finished_at = now()
        """,
        (day, notice_type, count),
    )
    conn.commit()


def fetch_day(client: httpx.Client, conn, day: date, page_size: int = 500) -> int:
    day_str = day.isoformat()
    day_count = 0
    for notice_type in NOTICE_TYPES:
        if is_day_done(conn, day, notice_type):
            print(f"  {day_str}/{notice_type}: juz w checkpointcie, pomijam")
            continue
        page = 1
        type_count = 0
        while True:
            notices, total_count = search_page(client, page, page_size, day_str, day_str, notice_type)
            if page == 1 and total_count > SAFE_DAILY_LIMIT:
                print(f"  UWAGA: {day_str}/{notice_type} ma {total_count} rekordow -- blisko limitu "
                      f"10k Elasticsearcha, potrzebne dalsze ciecie (np. po godzinach)")
            if not notices:
                break
            for n in notices:
                n["htmlBody"] = fetch_html_body(client, n["objectId"])
                bzp_row_id = upsert_notice(conn, n)
                if n["htmlBody"]:
                    parsed = parse_bzp_html_body(n["htmlBody"])
                    upsert_parsed_fields(conn, bzp_row_id, parsed)
                type_count += 1
                day_count += 1
                time.sleep(0.2)  # uprzejmosc wobec serwera
            conn.commit()
            # UWAGA (2026-08-04, sesja 2): NIE przerywac na "len(notices) < page_size" --
            # potwierdzone empirycznie, ze Board/Search PO CICHU IGNORUJE PageSize i zawsze
            # zwraca dokladnie 10 rekordow/strone, niezaleznie od zadanej wartosci (testowane
            # 10/20/50/100/500 -- zawsze body len=10, X-Pagination.PageSize=10). Warunek
            # "len(notices) < page_size" (10 < 500) byl wiec PRAWDZIWY na kazdej stronie,
            # przerywajac petle po pierwszych 10 rekordach kazdego dnia/typu -- cichy data
            # loss na kazdym dniu z >10 wynikow danego typu. Jedynym bezpiecznym warunkiem
            # konca jest pusta strona (jak w fetch_ted.py).
            page += 1
        mark_day_done(conn, day, notice_type, type_count)
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

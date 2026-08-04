"""Structural parser for BZP notice htmlBody (Rozporzadzenie form layout)."""

from __future__ import annotations

import json
import re
import sys
from pathlib import Path

_FIELD_RE = re.compile(
    r'<h3[^>]*>\s*(?P<code>\d+(?:\.\d+)*\.\))\s*(?P<label>[^:<]+):\s*'
    r'<span class="normal">\s*(?P<value>[^<]*?)\s*</span>'
)
_PART_MARKER_RE = re.compile(r'<h3[^>]*>\s*Cz(?:e|ę)(?:s|ś)(?:c|ć)\s+(?P<n>\d+)\s*</h3>')
_SECTION_RE = re.compile(
    r'<h2[^>]*>\s*SEKCJA\b[^<]*?(?:\(dla cz(?:e|ę)(?:s|ś)(?:c|ć)i\s*(?P<n>\d+)\))?\s*</h2>'
)


def parse_bzp_html_body(html: str) -> dict:
    """Wyciaga ponumerowane pola formularza BZP z htmlBody, strukturalnie (bez logiki biznesowej).

    Zwraca {"naglowek": {code: {etykieta, wartosc}}, "czesci": {n: {code: {...}}}}.
    Wartosci zostaja stringami jak w zrodle (np. "51660,00 PLN") -- typowanie i
    walidacja naleza do warstwy SQL, tak jak przy staging.clean_nip().
    """
    markers: list[tuple[int, int]] = []
    for m in _PART_MARKER_RE.finditer(html):
        markers.append((m.start(), int(m.group("n"))))
    for m in _SECTION_RE.finditer(html):
        if m.group("n"):
            markers.append((m.start(), int(m.group("n"))))
    markers.sort(key=lambda pair: pair[0])

    naglowek: dict[str, dict[str, str]] = {}
    czesci: dict[int, dict[str, dict[str, str]]] = {}

    for m in _FIELD_RE.finditer(html):
        code = m.group("code")
        section_num = int(code.split(".", 1)[0])
        entry = {"etykieta": m.group("label").strip(), "wartosc": m.group("value").strip()}

        part = None
        for marker_pos, n in markers:
            if marker_pos <= m.start():
                part = n
            else:
                break

        if part is None:
            # Zaden znacznik "Czesc N" jeszcze sie nie pojawil przed tym polem.
            if section_num <= 4:
                # SEKCJA I-IV przed pierwszym znacznikiem czesci to dane calej
                # procedury (np. 4.3.) Wartosc zamowienia), nie per-czesc.
                naglowek[code] = entry
                continue
            # SEKCJA V-VIII bez zadnego znacznika "Czesc N" -> postepowanie jednoczesciowe,
            # forma pomija numeracje czesci gdy nie ma czego rozroznic. Potwierdzone na
            # realnej probce (2026/BZP 00315920) -- bez tej reguly te pola trafialyby do
            # naglowka zamiast do czesci[1], niespojnie z postepowaniami wieloczesciowymi.
            part = 1

        # UWAGA (2026-08-04, sesja 2): SEKCJA IV ma pola PO-CZESCIOWE zagniezdzone pod
        # wlasnymi znacznikami "Czesc N" (np. 4.5.5.) Wartosc czesci, powtarzajace sie
        # per czesc) -- section_num<=4 NIE znaczy "zawsze naglowek". Sprawdzone na
        # realnej probce (2026/BZP 00315919, 3 czesci): bez routingu przez `part` tutaj,
        # 4.5.5.) ladowal do plaskiego naglowka i kazda kolejna czesc po cichu nadpisywala
        # poprzednia wartosc -- 2 z 3 wartosci czesci ginely bez sladu.
        czesci.setdefault(part, {})[code] = entry

    return {"naglowek": naglowek, "czesci": czesci}


def _smoke_test() -> None:
    sample_path = Path(__file__).parent.parent / "recon" / "bzp_sample_tenderresult.json"
    records = json.loads(sample_path.read_text(encoding="utf-8"))
    for rec in records:
        parsed = parse_bzp_html_body(rec["htmlBody"])
        print(f"=== {rec['bzpNumber']} ===")
        print(f"  pol w naglowku: {len(parsed['naglowek'])}")
        for n, pola in sorted(parsed["czesci"].items()):
            liczba_ofert = pola.get("6.1.)", {}).get("wartosc", "")
            cena_wygrana = pola.get("6.4.)", {}).get("wartosc", "")
            print(f"  Czesc {n} -> liczba_ofert={liczba_ofert!r} cena_wygrana={cena_wygrana!r}")


if __name__ == "__main__":
    _smoke_test()
    sys.exit(0)

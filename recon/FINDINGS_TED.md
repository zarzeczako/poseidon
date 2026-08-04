# Rekonesans TED — pierwsze ustalenia (2026-08-04)

W przeciwieństwie do BZP: TED ma prawdziwą, oficjalną dokumentację (`docs.ted.europa.eu`,
`developer.ted.europa.eu`) i pełny OpenAPI spec pod ręką — zero zgadywania endpointów.
Pełny spec pobrany: `recon/ted_api_v3.yaml` (14 000 linii, tysiące dostępnych pól eForms/BT-kodów).

## Endpoint (potwierdzone, bez autoryzacji)

```
POST https://api.ted.europa.eu/v3/notices/search
Content-Type: application/json

{
  "query": "organisation-country-buyer=POL AND publication-date>=20260101",
  "fields": ["publication-number", "tender-value", ...],
  "page": 1,
  "limit": 10
}
```

- **Query = "expert search" DSL**, nie parametry URL jak w BZP. Pola do query/fields buduje się i
  testuje na https://ted.europa.eu/en/search/expert-search (interaktywny builder).
- **Paginacja:** `page`+`limit` (max 250/strona, max 15k wyników przez paginację). Powyżej 15k trzeba
  `paginationMode: "ITERATION"` + `iterationNextToken` (scroll mode, bez górnego limitu) — potrzebne
  dla pełnej akwizycji historycznej, próbka dziś używała zwykłej paginacji.
- **`organisation-country-buyer=POL`** — potwierdzone, filtruje po kraju zamawiającego.
- Odpowiedź: `{"notices": [...], "totalNoticeCount": N, "iterationNextToken": ..., "timedOut": bool}`.

## Znalezisko 1 — cena I liczba ofert SĄ strukturalnymi polami JSON (w przeciwieństwie do BZP!)

To jest dobra wiadomość: po stronie TED nie trzeba żadnego HTML-parsera. Realny przykład z próbki:

```json
{
  "publication-number": "11-2026",
  "tender-value": "5649437.85",
  "tender-value-cur": "PLN",
  "winner-identifier": "813-384-41-03",
  "winner-selection-status": "selec-w",
  "received-submissions-type-val": "1"
}
```

`tender-value` = wartość wygranej oferty, `received-submissions-type-val` = prawdopodobnie liczba
otrzymanych ofert (do potwierdzenia: sprawdzić towarzyszące pole `received-submissions-type-code`,
bo może rozróżniać "liczba ofert" od "liczba wniosków o dopuszczenie" w różnych trybach postępowania).

**Ważne dla matchingu, nie tylko dla flag:** `tender-value` to cena WYGRANEJ oferty (wynik), nie
szacunek. Do dopasowania BZP↔TED (fuzzy match po wartości ±2%) trzeba użyć pola **szacunkowego**, nie
`tender-value` — inaczej porównywalibyśmy szacunek BZP z ceną końcową TED, co jest dokładnie tym
zniekształceniem, które projekt ma mierzyć (premia = różnica między szacunkiem a ceną). Kandydat:
`estimated-value-cur-lot` (widoczny w spec, jeszcze nie przetestowany osobno).

## Znalezisko 2 — identyfikator zamawiającego (`organisation-identifier-buyer`) jest bałaganiarski,
## i to bardziej niż zakładaliśmy na starcie

Pierwotne założenie (z pierwszej wiadomości w tej sesji) było: "TED ma NIP z prefiksem np. 'PL'".
Realne wartości z próbki 3 rekordów:

| Wartość surowa | Po `staging.clean_nip()` | Komentarz |
|---|---|---|
| `"NIP: 525-000-80-57"` | `5250008057` | Etykieta + myślniki, ale `clean_nip()` już to ogarnia |
| `"090538318"` | `NULL` | **9 cyfr — to REGON, nie NIP!** `clean_nip()` poprawnie odrzuca (wymaga dokładnie 10 cyfr) |
| `"712-010-69-11"` | `7120106911` | Myślniki, bez etykiety |

**To realna luka w strategii matchingu, nie tylko brzydkie dane:** część zamawiających w TED ma wpisany
REGON zamiast NIP. Dla takich rekordów `nip_zamawiajacy` po obu stronach się nie zgodzi (BZP ma NIP,
`clean_nip()` na TED zwróci NULL dla REGON-u) — czyli realne dopasowania będą po cichu ginąć w
fuzzy-matchu, nie tylko w przypadkach opisanych w `POSEIDON_GUIDE.md` (Poziom 2). Do rozważania: fallback
na REGON (wymaga też czyszczenia REGON po stronie BZP, którego jeszcze nie mamy) albo pogodzenie się z
utratą tych par i uwzględnienie tego w karcie ograniczeń zbioru.

## Znalezisko 3 — skala

`organisation-country-buyer=POL` bez żadnych innych filtrów: **287 868** ogłoszeń w całej historii TED.
Z samym filtrem `publication-date>=20260101` (2026 rok do dziś): **74 333** — nieproporcjonalnie dużo
jak na ~7 miesięcy vs. całą historię od 1993 r., więc **podejrzewam, że filtr daty nie działa tak, jak
zakładam** (może `>=20260101` parsuje się inaczej niż oczekiwana data, albo eForms zwiększyło liczbę
ogłoszeń na postępowanie od 2022 r.). Nie zbadane do końca — flaguję jako coś do zweryfikowania przed
poleganiem na filtrach dat w prawdziwym pipeline.

## Nieprzebadane w tym przebiegu

- Dokładna nazwa pola "typ ogłoszenia" (odpowiednik `NoticeType` z BZP) — trzeba, żeby filtrować tylko
  ogłoszenia o wyniku, tak jak `TenderResultNotice` w BZP
- `estimated-value-cur-lot` nieprzetestowane bezpośrednio (patrz Znalezisko 1)
- `received-submissions-type-code` nieprzetestowane (czy faktycznie rozróżnia typy zgłoszeń)
- Dlaczego filtr daty daje nieproporcjonalnie dużo wyników (Znalezisko 3)
- Bulk XML/FTP download (`ted.europa.eu/en/simap/xml-bulk-download`, z koncepcji) — search API najpewniej
  wystarczy do próbek i bieżącej akwizycji, ale do pełnej historii 2021-2026 może się przydać masowe
  pobieranie zamiast page-by-page przez Search API (15k limit na zwykłą paginację, ITERATION bez limitu
  ale wolniejsze) — do oceny przy projektowaniu pełnej akwizycji, nie teraz

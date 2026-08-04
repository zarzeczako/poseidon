# STATE.md — P.O.S.E.I.D.O.N. Protokół Ciągłości

> Jedyne źródło prawdy o tym, gdzie stoi projekt. Aktualizowane po każdym większym kamieniu milowym — silnie, bez pytania o zgodę. Jeśli sesja się urwie albo przejmie ją inny agent: zacznij tutaj, potem `POSEIDON_GUIDE.md`.

**Ostatnia aktualizacja:** 2026-08-04
**Aktualna faza:** Faza 1 (Akwizycja) — w toku. BZP: rekonesans + parser SEKCJA VI gotowe i zweryfikowane. TED: pierwszy rekonesans zrobiony (Search API v3, w pełni udokumentowane, dużo czystsze niż BZP) — cena i liczba ofert to tam zwykłe pola JSON, HTML-parser niepotrzebny. Neon nadal czeka na założenie konta przez Architekta — to teraz główny bloker.

---

## 1. Rebranding

NEMEZIS/HELIOS → **P.O.S.E.I.D.O.N.**

**P**ublic **O**rder & **S**ystemic **E**rosion **I**nvestigative **D**ata **O**bservation **N**etwork

Motyw: bóg mórz, trzęsień ziemi i sztormów. Nurkujemy w mętnych wodach zamówień publicznych, wykrywamy podwodne prądy (ukryte powiązania podmiotów) i wywołujemy sejsmiczny wstrząs w sposobie audytowania środków publicznych.

Dokument źródłowy koncepcji: [`NEMEZIS_koncepcja.md`](./NEMEZIS_koncepcja.md) — nazwa pliku historyczna, merytorycznie w 100% aktualny. Terminologię (NEMEZIS → POSEIDON, NRI → do ustalenia) podmieniamy sukcesywnie, nie przez masowy find-replace.

## 2. Środowisko techniczne

- **Katalog roboczy:** `C:\Users\micha\Desktop\poseidon`
- **Git:** brak repozytorium — do założenia, termin nieustalony (nie blokuje Fazy 1)
- **OS:** Windows 11
- **Planowany stack:** Python (Extract+Load: klienci API, strukturalny XML→JSON dla TED, bez logiki biznesowej) → **PostgreSQL** (staging/core, zmiana z DuckDB — patrz `POSEIDON_GUIDE.md`) → Power BI (star schema + DAX, Import Mode, refresh tygodniowy) → eksport Excel (openpyxl/XlsxWriter) jako "last mile"
- **PostgreSQL — hosting:** ✅ Neon (managed serverless) — zatwierdzone 2026-08-03, patrz `POSEIDON_GUIDE.md`. Czeka na: Architekt zakłada projekt/bazę na Neon i przekazuje connection string przez `.env` (nie na czacie)
- **Pliki w katalogu:** `NEMEZIS_koncepcja.md` (koncepcja źródłowa), `STATE.md`, `POSEIDON_GUIDE.md`, `sql/001_staging.sql` (schemat staging + funkcje NIP), `sql/002_core_reconciliation.sql` (widoki godzenia BZP↔TED), `.gitignore`, `.env.example` (szablon zmiennych środowiskowych), `etl/parse_bzp_form.py` (parser SEKCJA VI-VIII), `recon/FINDINGS.md` (BZP) + `recon/FINDINGS_TED.md` (TED) + próbki JSON + `recon/ted_api_v3.yaml` (pełny OpenAPI spec TED)
- **Python:** ✅ 3.14.6, zainstalowany i zweryfikowany 2026-08-04 (działa i w Bash, i w PowerShell)

## 3. Ukończone zadania

- [x] Odczytanie i przyswojenie pełnej koncepcji projektu
- [x] Rebranding NEMEZIS → P.O.S.E.I.D.O.N. (nazewnictwo, motyw)
- [x] Inicjalizacja `STATE.md` i `POSEIDON_GUIDE.md`
- [x] Ustalenie dynamiki współpracy: Architekt decyduje o strukturze/ryzyku/statystyce/narracji, Claude wykonuje inżynierię danych dopiero po zatwierdzeniu podejścia
- [x] Architekt zaprojektował warstwę Faza 1: Postgres, Strict ELT, reguły hierarchii źródeł (BZP=tekst, TED=słowniki), tolerancje fuzzy-matchu (±7 dni, ±2%)
- [x] Claude zweryfikował projekt, znalazł i naprawił lukę fan-out w fuzzy-matchu (wymóg wzajemnego najlepszego dopasowania), zbudował szkielet `sql/001_staging.sql` + `sql/002_core_reconciliation.sql`
- [x] Hosting (Neon) i konflikt kwot BZP/TED zatwierdzone przez Architekta 2026-08-03
- [x] Claude znalazł prawdziwy endpoint BZP (`mo-board/api/v1/notice`, bez autoryzacji), pobrał małą próbkę (TenderResultNotice + ContractNotice) — patrz `recon/FINDINGS.md`. TED jeszcze nietknięty.
- [x] Architekt przejrzał 4 znaleziska 2026-08-04: Znalezisko 1 (flaga progu UE) zatwierdzone bez zmian, Znalezisko 2 (unnest contractors) rozwiązane wg pomysłu Architekta + sformalizowane (CASE/jsonb_typeof/WITH ORDINALITY), Znalezisko 3 (liczba ofert/cena) rozwiązane przez Claude'a — dane są w htmlBody, ale to ustandaryzowany formularz z numerowanymi polami, nie dowolny HTML, Znalezisko 4 (flaga osoby fizycznej) zatwierdzone
- [x] `sql/002_core_reconciliation.sql` przepisany: prawdziwe nazwy pól BZP, filtr `czy_powyzej_progu_ue`, nowy widok `staging.v_bzp_parts` (unnest po częściach)

## 4. Aktywne blokery

- Brak repozytorium Git — nieblokujące na razie
- Zero pobranych danych — SQL istnieje, ale nic jeszcze nie działało na realnych rekordach
- ~~Konflikt kwot BZP vs TED~~ — ✅ zatwierdzone 2026-08-03: trzymamy obie kolumny + flagę rozbieżności (patrz `POSEIDON_GUIDE.md`)
- ~~Hosting Postgres~~ — ✅ zatwierdzone 2026-08-03: Neon (patrz `POSEIDON_GUIDE.md`)
- ~~Kto prowadzi rekonesans~~ — ✅ ustalone: Claude pobiera próbki, Architekt analizuje i decyduje
- ~~Liczba ofert / cena nie są polami JSON~~ — ✅ rozwiązane 2026-08-04: są w `htmlBody` jako ustandaryzowany formularz z numerowanymi polami (SEKCJA VI), nie dowolny HTML. Patrz `recon/FINDINGS.md`, ROZWIĄZANIE Znalezisko 3.
- ~~Unnest wieloczęściowych postępowań~~ — ✅ rozwiązane 2026-08-04, zaimplementowane w `staging.v_bzp_parts`
- ~~Gdzie parsować SEKCJA VI~~ — ✅ zatwierdzone 2026-08-04: Python, regex strukturalny. `etl/parse_bzp_form.py` napisany, zwalidowany 1:1 przez odpowiednik w PowerShell na 3 realnych próbkach (patrz `POSEIDON_GUIDE.md`) — sam plik `.py` jeszcze nieuruchomiony (patrz Python poniżej)
- ~~Python niezainstalowany~~ — ✅ rozwiązane 2026-08-04: Architekt zainstalował Python 3.14.6. `etl/parse_bzp_form.py` uruchomiony naprawdę (nie tylko przez proxy w PowerShell) — wyniki dla liczby ofert/ceny identyczne z walidacją. Drobna, nieistotna rozbieżność w liczbie pól nagłówka (29 vs 25, 27 vs 25) — najpewniej dlatego, że test w PowerShell dopasowywał cudzysłów wildcardem, a prawdziwy Python dokładnie; nie dotyczy pól SEKCJA VI-VIII, które faktycznie liczą się do F1/F4
- **Czeka na Architekta (główny bloker):** założenie projektu/bazy na Neon i przekazanie connection string przez `.env` — nic nie da się realnie uruchomić bez tego
- ~~TED nietknięty~~ — ✅ pierwszy rekonesans zrobiony 2026-08-04: endpoint, brak autoryzacji, kształt pól. Patrz `recon/FINDINGS_TED.md`
- **Nowe (TED):** część zamawiających w TED ma REGON zamiast NIP jako identyfikator — dopasowanie BZP↔TED po `nip_zamawiajacy` po cichu ominie te przypadki. Fallback nierozstrzygnięty (patrz `recon/FINDINGS_TED.md`, Znalezisko 2)
- **Nowe (TED):** `wartosc_szacunkowa` w `v_ted_parsed` to na razie NULL — pole `tender-value` istnieje, ale to cena WYGRANEJ, nie szacunek; użycie go do matchingu zniekształcałoby wynik. Kandydat `estimated-value-cur-lot` do potwierdzenia
- Filtr daty w TED Search API dał podejrzanie dużo wyników (74k dla samego 2026 vs 288k za całą historię) — niezweryfikowane, czy filtr działa tak jak zakładam (patrz `recon/FINDINGS_TED.md`, Znalezisko 3)

## 5. Decyzje dot. lineage danych

- **Landing zone:** `staging.bzp_notices_raw` (JSONB, 1 wiersz = 1 odpowiedź API) i `staging.ted_notices_raw` (raw XML + JSONB równolegle, dla audytu) — niemutowalne, pełna historia przez `fetched_at`
- **Warstwy:** `staging` (surowe + nazwane-kolumny-z-JSONB w `v_*_parsed`) → `core` (widoki godzenia, `postepowania_polaczone` jako punkt wejścia do przyszłego modelu gwiazdy w Fazie 6)
- **Klucz łączący BZP↔TED:** dwupoziomowy — (1) twarda referencja TED w BZP, gdy dostępna, (2) fuzzy: NIP zamawiającego (czyszczony regexem, walidowany sumą kontrolną) + data ±7 dni + wartość ±2%, wymagające wzajemnego najlepszego dopasowania (nie zwykły JOIN — patrz `POSEIDON_GUIDE.md`)
- **Audytowalność dopasowań:** każdy połączony rekord niesie `match_method` (`exact_reference` / `fuzzy_heuristic` / `bzp_only` / `ted_only`); niepewne dopasowania lądują w `core.v_matches_needs_review`, nie znikają po cichu
- **[2026-08-03] Filtr progu UE:** BZP ma wprost pole `isTenderAmountBelowEU` (bool) — używamy go do filtrowania kandydatów do godzenia z TED zamiast heurystyki. Realny endpoint: `https://ezamowienia.gov.pl/mo-board/api/v1/notice` (nie `mo-client-board` z koncepcji — to był adres frontendu)
- **[2026-08-03] Ziarno potwierdzone empirycznie, ale wymaga unnest:** wieloczęściowe postępowania mają `procedureResult` (wyniki rozdzielone średnikiem) i `contractors` (tablica, pozycyjnie zgodna) — trzeba je rozpakować, żeby dostać 1 wiersz = 1 część. Pułapka: przy 1 części `contractors` jest gołym obiektem, nie tablicą jednoelementową. Szczegóły: `recon/FINDINGS.md`
- **[2026-08-04] `staging.v_bzp_parts`:** nowy widok, rozpakowuje BZP do ziarna "1 część" (normalizacja kształtu + `WITH ORDINALITY`, patrz `POSEIDON_GUIDE.md`). Na razie tylko po stronie BZP — kolejność względem dopasowania do TED (przed czy po unnest) nierozstrzygnięta, bo nie wiadomo, czy TED raportuje wartość per-część
- **[2026-08-04] Endpointy BZP (potwierdzone na żywo):** `Board/Search` (lista, prawdziwa paginacja: `PageNumber`/`PageSize`/`SortingColumnName`/`SortingDirection`), `Board/GetNoticeDetailsById` (nagłówek/metadata), `Board/GetNoticeHtmlBodyById` (= pole `htmlBody`, ten sam content), `Board/GetLastVersionFormPreview` (też tylko HTML, nie ma czystszych danych). Żaden z nich nie ma liczby-ofert/ceny jako strukturalnego pola — tylko w tekście HTML
- **[2026-08-04] TED Search API v3:** `POST https://api.ted.europa.eu/v3/notices/search`, bez autoryzacji, w pełni udokumentowane (`recon/ted_api_v3.yaml`). Query to osobny DSL ("expert search", np. `organisation-country-buyer=POL AND publication-date>=20260101`), nie parametry URL. Paginacja: `page`+`limit` (max 15k), albo `paginationMode: ITERATION` + `iterationNextToken` bez limitu (scroll mode) — potrzebne do pełnej akwizycji historycznej. W przeciwieństwie do BZP: cena (`tender-value`) i prawdopodobnie liczba ofert (`received-submissions-type-val`) to zwykłe pola JSON, zero HTML-parsingu po stronie TED

## 6. Następne kroki

1. **Architekt (blokuje wszystko dalsze):** założyć projekt + bazę na Neon, wkleić connection string do lokalnego `.env` (szablon: `.env.example`) — nie na czacie
2. Potwierdzić `estimated-value-cur-lot` jako pole szacunku w TED (curl/próbka) i uzupełnić `v_ted_parsed`
3. Zdecydować fallback NIP/REGON dla zamawiających TED bez NIP (patrz §4)
4. Uruchomienie SQL na Neon, potem pierwszy kod klienta API (Claude, Python Extract+Load) dla obu źródeł

## 7. Mapa faz

| Faza | Zakres | Prowadzi | Status |
|---|---|---|---|
| 0 | Inicjalizacja, rebranding, dokumentacja | Wspólnie | ✅ |
| 1 | Rozpoznanie API BZP/TED, pełna akwizycja, parser eForms, landing zone | Claude (pod nadzorem) | 🔄 w toku |
| 2 | Wzbogacenie: KRS, plik płaski VAT, REGON, BDL | Claude | ⬜ |
| 3 | Entity resolution + graf powiązań, ręczna walidacja 500 par | Wspólnie | ⬜ |
| 4 | Definicja 11 flag ryzyka (F1–F11) + peer groups | Architekt | ⬜ |
| 5 | Matching + regresja z efektami stałymi + bootstrap + walidacja indeksu na KIO/NIK | Architekt | ⬜ |
| 6 | Model gwiazdy + ~30 miar DAX + grupy obliczeniowe | Architekt (Claude tłumaczy logikę) | ⬜ |
| 7 | Raport Power BI (5 stron) + generator Excel "Top 50 Zablokowanych Par" | Architekt | ⬜ |
| 8 | Publikacja: Zenodo (DOI), GitHub, whitepaper, dystrybucja | Wspólnie | ⬜ |

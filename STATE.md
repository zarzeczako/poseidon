# STATE.md — P.O.S.E.I.D.O.N. Protokół Ciągłości

> Jedyne źródło prawdy o tym, gdzie stoi projekt. Aktualizowane po każdym większym kamieniu milowym — silnie, bez pytania o zgodę. Jeśli sesja się urwie albo przejmie ją inny agent: zacznij tutaj, potem `POSEIDON_GUIDE.md`.

**Ostatnia aktualizacja:** 2026-08-03
**Aktualna faza:** Faza 1 (Akwizycja) — w toku. SQL godzenia BZP↔TED gotowy. Pierwszy przebieg rekonesansu BZP zrobiony (Claude, próbka mała) — czeka na analizę Architekta, patrz `recon/FINDINGS.md`.

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
- **Pliki w katalogu:** `NEMEZIS_koncepcja.md` (koncepcja źródłowa), `STATE.md`, `POSEIDON_GUIDE.md`, `sql/001_staging.sql` (schemat staging + funkcje NIP), `sql/002_core_reconciliation.sql` (widoki godzenia BZP↔TED), `.gitignore`, `.env.example` (szablon zmiennych środowiskowych), `recon/` (próbki realnych danych BZP + `FINDINGS.md`)

## 3. Ukończone zadania

- [x] Odczytanie i przyswojenie pełnej koncepcji projektu
- [x] Rebranding NEMEZIS → P.O.S.E.I.D.O.N. (nazewnictwo, motyw)
- [x] Inicjalizacja `STATE.md` i `POSEIDON_GUIDE.md`
- [x] Ustalenie dynamiki współpracy: Architekt decyduje o strukturze/ryzyku/statystyce/narracji, Claude wykonuje inżynierię danych dopiero po zatwierdzeniu podejścia
- [x] Architekt zaprojektował warstwę Faza 1: Postgres, Strict ELT, reguły hierarchii źródeł (BZP=tekst, TED=słowniki), tolerancje fuzzy-matchu (±7 dni, ±2%)
- [x] Claude zweryfikował projekt, znalazł i naprawił lukę fan-out w fuzzy-matchu (wymóg wzajemnego najlepszego dopasowania), zbudował szkielet `sql/001_staging.sql` + `sql/002_core_reconciliation.sql`
- [x] Hosting (Neon) i konflikt kwot BZP/TED zatwierdzone przez Architekta 2026-08-03
- [x] Claude znalazł prawdziwy endpoint BZP (`mo-board/api/v1/notice`, bez autoryzacji), pobrał małą próbkę (TenderResultNotice + ContractNotice) — patrz `recon/FINDINGS.md`. TED jeszcze nietknięty.

## 4. Aktywne blokery

- Brak repozytorium Git — nieblokujące na razie
- Zero pobranych danych — SQL istnieje, ale nic jeszcze nie działało na realnych rekordach
- ~~Konflikt kwot BZP vs TED~~ — ✅ zatwierdzone 2026-08-03: trzymamy obie kolumny + flagę rozbieżności (patrz `POSEIDON_GUIDE.md`)
- ~~Hosting Postgres~~ — ✅ zatwierdzone 2026-08-03: Neon (patrz `POSEIDON_GUIDE.md`)
- ~~Kto prowadzi rekonesans~~ — ✅ ustalone: Claude pobiera próbki, Architekt analizuje i decyduje
- **Czeka na Architekta:** założenie projektu/bazy na Neon i przekazanie connection string przez `.env`
- **Czeka na Architekta (krytyczne):** `liczba ofert` i `cena wybranej oferty` — czyli dane pod F1_JednaOferta i F4_CenaVsSzacunek, serce całego NRI/PRI — NIE występują jako pola JSON w BZP, tylko (prawdopodobnie) w embedded HTML ogłoszenia. Trzeba ocenić, czy da się to parsować wiarygodnie, zanim zainwestujemy dalej w Fazę 1. Patrz `recon/FINDINGS.md`, Znalezisko 3.
- Nazwy pól w `payload->>'...'` w `sql/002_core_reconciliation.sql` to nadal placeholdery — mamy już część realnych nazw z rekonesansu (patrz §5), ale pełne przepisanie SQL czeka, aż ziarno/unnest i kwestia liczby-ofert zostaną rozstrzygnięte, żeby nie przepisywać dwa razy

## 5. Decyzje dot. lineage danych

- **Landing zone:** `staging.bzp_notices_raw` (JSONB, 1 wiersz = 1 odpowiedź API) i `staging.ted_notices_raw` (raw XML + JSONB równolegle, dla audytu) — niemutowalne, pełna historia przez `fetched_at`
- **Warstwy:** `staging` (surowe + nazwane-kolumny-z-JSONB w `v_*_parsed`) → `core` (widoki godzenia, `postepowania_polaczone` jako punkt wejścia do przyszłego modelu gwiazdy w Fazie 6)
- **Klucz łączący BZP↔TED:** dwupoziomowy — (1) twarda referencja TED w BZP, gdy dostępna, (2) fuzzy: NIP zamawiającego (czyszczony regexem, walidowany sumą kontrolną) + data ±7 dni + wartość ±2%, wymagające wzajemnego najlepszego dopasowania (nie zwykły JOIN — patrz `POSEIDON_GUIDE.md`)
- **Audytowalność dopasowań:** każdy połączony rekord niesie `match_method` (`exact_reference` / `fuzzy_heuristic` / `bzp_only` / `ted_only`); niepewne dopasowania lądują w `core.v_matches_needs_review`, nie znikają po cichu
- **[2026-08-03] Filtr progu UE:** BZP ma wprost pole `isTenderAmountBelowEU` (bool) — używamy go do filtrowania kandydatów do godzenia z TED zamiast heurystyki. Realny endpoint: `https://ezamowienia.gov.pl/mo-board/api/v1/notice` (nie `mo-client-board` z koncepcji — to był adres frontendu)
- **[2026-08-03] Ziarno potwierdzone empirycznie, ale wymaga unnest:** wieloczęściowe postępowania mają `procedureResult` (wyniki rozdzielone średnikiem) i `contractors` (tablica, pozycyjnie zgodna) — trzeba je rozpakować, żeby dostać 1 wiersz = 1 część. Pułapka: przy 1 części `contractors` jest gołym obiektem, nie tablicą jednoelementową. Szczegóły: `recon/FINDINGS.md`

## 6. Następne kroki

1. **Architekt:** przejrzeć `recon/FINDINGS.md` + surowe próbki, w szczególności zbadać `htmlBody` pod kątem liczby ofert/ceny (Znalezisko 3) — to decyduje, jak trudna realnie jest Faza 1
2. Architekt zakłada projekt + bazę na Neon, wkleja connection string do lokalnego `.env` (szablon: `.env.example`) — nie na czacie
3. Rozszerzenie rekonesansu: TED (nietknięty), większa próbka BZP, sprawdzenie paginacji/`totalCount`
4. Dopiero po 1-3: przepisanie `sql/002_core_reconciliation.sql` na realne nazwy pól + unnest po częściach, decyzja o źródle liczby-ofert/ceny
5. Uruchomienie SQL na Neon, potem pierwszy kod klienta API (Claude, Python Extract+Load)

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

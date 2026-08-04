-- P.O.S.E.I.D.O.N. -- Faza 1: godzenie BZP <-> TED
-- BZP: nazwy pol POTWIERDZONE rekonesansem 2026-08-03/04 (prawdziwe zapytania do
--      https://ezamowienia.gov.pl/mo-board/api/v1/notice, patrz recon/FINDINGS.md).
-- TED: nazwy pol payload->>'...' to nadal PLACEHOLDERY -- TED jeszcze nietkniety.
-- Kolumny kwota_bzp/kwota_ted: obie trzymane celowo (decyzja zatwierdzona 2026-08-03) -- patrz POSEIDON_GUIDE.md.

CREATE SCHEMA IF NOT EXISTS core;

-- ============================================================
-- Warstwa posrednia: nazwane kolumny z JSONB
-- ============================================================

CREATE OR REPLACE VIEW staging.v_bzp_parsed AS
SELECT
    id AS bzp_row_id,
    notice_id AS bzp_notice_id,
    staging.clean_nip(payload->>'organizationNationalId')   AS nip_zamawiajacy,
    -- REGON zamawiajacego jest tylko w htmlBody (SEKCJA I, "1.3.) Krajowy Numer
    -- Identyfikacyjny: REGON XXXXXXXXX"), nie ma go jako czyste pole JSON. BZP-owy NIP
    -- jest niezawodny (potwierdzone na probce), wiec REGON jest tu potrzebny wylacznie
    -- jako klucz do dopasowania z TED, gdy TED zgloszil REGON zamiast NIP -- nie do
    -- identyfikacji zamawiajacego po stronie BZP samej w sobie. Wzorzec zwalidowany na
    -- realnym htmlBody (recon/) przed wdrozeniem.
    staging.clean_regon(substring(payload->>'htmlBody' from
        'Krajowy Numer Identyfikacyjny:\s*<span class="normal">\s*REGON\s*(\d+)'))
                                                              AS regon_zamawiajacy,
    (payload->>'publicationDate')::timestamptz::date         AS data_publikacji,
    -- Brak wprost pola "wartosc szacunkowa" w JSON listy -- do potwierdzenia w Fazie
    -- godzenia po zbudowaniu warstwy wyciagania pol z SEKCJA IV htmlBody (patrz dol pliku).
    NULL::numeric                                             AS wartosc_szacunkowa,
    NULL::text                                                AS ted_reference,  -- twarda referencja TED w BZP -- pole jeszcze nie zlokalizowane, patrz FINDINGS.md
    NOT (payload->>'isTenderAmountBelowEU')::boolean          AS czy_powyzej_progu_ue,  -- Znalezisko 1: prawdziwa flaga z API, nie heurystyka
    payload
FROM staging.bzp_notices_raw;

CREATE OR REPLACE VIEW staging.v_ted_parsed AS
SELECT
    id AS ted_row_id,
    notice_id AS ted_notice_id,
    -- Potwierdzone na Search API v3 (recon/FINDINGS_TED.md): identyfikator bywa NIP
    -- (czasem z etykietą "NIP: " i myslnikami -- clean_nip() to ogarnia) ALBO REGON
    -- (9 cyfr). To samo surowe pole probujemy wyczyscic dwoma funkcjami -- ktorakolwiek
    -- pasuje do dlugosci, ta wygrywa. Architekt zdecydowal (2026-08-04): NIP ma
    -- pierwszenstwo w matchingu, REGON tylko jako fallback dla par, ktore nie znalazly
    -- dopasowania po NIP (patrz core.v_matches_fuzzy_regon_candidates nizej).
    staging.clean_nip(payload->>'organisation-identifier-buyer')   AS nip_zamawiajacy,
    staging.clean_regon(payload->>'organisation-identifier-buyer') AS regon_zamawiajacy,
    (payload->>'publication-date')::date                         AS data_publikacji,
    -- UWAGA: NIE 'tender-value' (to cena WYGRANEJ oferty -- wynik, nie szacunek).
    -- Do matchingu potrzebny szacunek po stronie TED, kandydat 'estimated-value-cur-lot',
    -- jeszcze niepotwierdzony bezposrednio (patrz FINDINGS_TED.md Znalezisko 1). Uzycie
    -- tender-value do matchingu zniek​stalcaloby wynik, bo roznica szacunek<->cena
    -- koncowa to dokladnie to, co ten projekt mierzy.
    NULL::numeric                                                 AS wartosc_szacunkowa,
    payload
FROM staging.ted_notices_raw;

-- ============================================================
-- Rozpakowanie wieloczesciowych postepowan BZP do ziarna "1 czesc" (F_Postepowania).
-- Potwierdzone empirycznie na realnych danych (recon/FINDINGS.md, Znalezisko 2):
-- `procedureResult` to string rozdzielony srednikiem, `contractors` to tablica
-- POZYCYJNIE zgodna z nim -- ale TYLKO gdy czesci jest >1. Przy dokladnie 1 czesci
-- `contractors` jest golym obiektem JSON, nie tablica jednoelementowa. Normalizujemy
-- to jawnie (Twoj pomysl z "ifem", tu: CASE + jsonb_typeof), zanim probujemy rozpakowac.
-- ============================================================

CREATE OR REPLACE VIEW staging.v_bzp_parts AS
WITH normalized AS (
    SELECT
        id AS bzp_row_id,
        notice_id AS bzp_notice_id,
        payload,
        CASE jsonb_typeof(payload->'contractors')
            WHEN 'array'  THEN payload->'contractors'
            WHEN 'object' THEN jsonb_build_array(payload->'contractors')
            ELSE '[]'::jsonb
        END AS contractors_arr,
        string_to_array(payload->>'procedureResult', ';') AS results_arr
    FROM staging.bzp_notices_raw
)
SELECT
    n.bzp_row_id,
    n.bzp_notice_id,
    c.ord AS czesc_nr,
    trim(n.results_arr[c.ord]) AS wynik_czesci,
    c.contractor ->> 'contractorName' AS wykonawca_nazwa,
    staging.clean_nip(c.contractor ->> 'contractorNationalId') AS wykonawca_nip,
    -- Znalezisko 4 (zatwierdzone): contractorNationalId bywa np. "brak - podmiot nie
    -- prowadzacy dzialalnosci gospodarczej" -- to NIE jest brak danych, to zwyciezca
    -- bedacy osoba fizyczna. Odrozniamy od pustego rekordu (czesc uniewazniona), gdzie
    -- contractorNationalId jest NULL.
    ((c.contractor ->> 'contractorNationalId') IS NOT NULL
        AND staging.clean_nip(c.contractor ->> 'contractorNationalId') IS NULL)
        AS wykonawca_czy_osoba_fizyczna
FROM normalized n
CROSS JOIN LATERAL jsonb_array_elements(n.contractors_arr) WITH ORDINALITY AS c(contractor, ord);

-- UWAGA: to jest warstwa TYLKO po stronie BZP. Czy rozpakowanie po czesciach ma sie
-- dziac PRZED czy PO dopasowaniu do TED (ponizej) -- nierozstrzygniete, bo nie wiadomo
-- jeszcze, czy TED raportuje wartosc per-czesc czy tylko sumarycznie dla postepowania.
-- Dopasowanie BZP<->TED ponizej dziala wciaz na poziomie calego ogloszenia.

-- ============================================================
-- Poziom 1 dopasowania: twarda referencja (BZP zna numer ogloszenia TED)
-- ============================================================

CREATE OR REPLACE VIEW core.v_matches_exact AS
SELECT
    b.bzp_row_id,
    t.ted_row_id,
    'exact_reference'::text AS match_method
FROM staging.v_bzp_parsed b
JOIN staging.v_ted_parsed t ON t.ted_notice_id = b.ted_reference
WHERE b.ted_reference IS NOT NULL;

-- ============================================================
-- Poziom 2 dopasowania: fuzzy, tylko dla par bez twardej referencji, i tylko dla
-- postepowan POWYZEJ progu UE (Znalezisko 1: czy_powyzej_progu_ue z samego BZP,
-- zamiast zgadywac kto w ogole powinien szukac pary w TED).
-- Kandydat musi byc WZAJEMNIE najlepszym dopasowaniem po obu stronach (podwojny
-- ranking) -- inaczej jeden BZP moglby "ukrasc" dwa rekordy TED (albo odwrotnie),
-- gdy zamawiajacy publikuje 2+ podobne przetargi w tym samym tygodniu.
--
-- Dwie warstwy, w tej kolejnosci (Architekt, 2026-08-04: "bardziej ufam NIPowi"):
--   2a. fuzzy po NIP (pierwszenstwo)
--   2b. fuzzy po REGON, TYLKO dla BZP-rekordow ktore NIE dostaly dopasowania w 2a --
--       bo TED czasem ma REGON zamiast NIP w tym samym polu (FINDINGS_TED.md, Znal. 2)
-- ============================================================

-- --- 2a: NIP ---

CREATE OR REPLACE VIEW core.v_matches_fuzzy_nip_candidates AS
SELECT
    b.bzp_row_id,
    t.ted_row_id,
    ABS(b.data_publikacji - t.data_publikacji) AS dni_roznicy,
    ABS(b.wartosc_szacunkowa - t.wartosc_szacunkowa) / NULLIF(b.wartosc_szacunkowa, 0) AS pct_roznicy_wartosci,
    (ABS(b.data_publikacji - t.data_publikacji)::numeric / 7.0) +
    (ABS(b.wartosc_szacunkowa - t.wartosc_szacunkowa) / NULLIF(b.wartosc_szacunkowa, 0) / 0.02) AS combined_score
FROM staging.v_bzp_parsed b
JOIN staging.v_ted_parsed t
    ON t.nip_zamawiajacy = b.nip_zamawiajacy
    AND ABS(b.data_publikacji - t.data_publikacji) <= 7
    AND ABS(b.wartosc_szacunkowa - t.wartosc_szacunkowa) / NULLIF(b.wartosc_szacunkowa, 0) <= 0.02
WHERE b.czy_powyzej_progu_ue
  AND b.nip_zamawiajacy IS NOT NULL
  AND b.bzp_row_id NOT IN (SELECT bzp_row_id FROM core.v_matches_exact)
  AND t.ted_row_id NOT IN (SELECT ted_row_id FROM core.v_matches_exact);

CREATE OR REPLACE VIEW core.v_matches_fuzzy_nip AS
SELECT bzp_row_id, ted_row_id, 'fuzzy_heuristic_nip'::text AS match_method
FROM (
    SELECT *,
        ROW_NUMBER() OVER (PARTITION BY bzp_row_id ORDER BY combined_score) AS rn_bzp,
        ROW_NUMBER() OVER (PARTITION BY ted_row_id ORDER BY combined_score) AS rn_ted
    FROM core.v_matches_fuzzy_nip_candidates
) ranked
WHERE rn_bzp = 1 AND rn_ted = 1;   -- wzajemnie najlepsze dopasowanie -> bezpieczne 1:1

-- --- 2b: REGON, tylko dla tego, co zostalo niedopasowane po NIP ---

CREATE OR REPLACE VIEW core.v_matches_fuzzy_regon_candidates AS
SELECT
    b.bzp_row_id,
    t.ted_row_id,
    ABS(b.data_publikacji - t.data_publikacji) AS dni_roznicy,
    ABS(b.wartosc_szacunkowa - t.wartosc_szacunkowa) / NULLIF(b.wartosc_szacunkowa, 0) AS pct_roznicy_wartosci,
    (ABS(b.data_publikacji - t.data_publikacji)::numeric / 7.0) +
    (ABS(b.wartosc_szacunkowa - t.wartosc_szacunkowa) / NULLIF(b.wartosc_szacunkowa, 0) / 0.02) AS combined_score
FROM staging.v_bzp_parsed b
JOIN staging.v_ted_parsed t
    ON t.regon_zamawiajacy = b.regon_zamawiajacy
    AND ABS(b.data_publikacji - t.data_publikacji) <= 7
    AND ABS(b.wartosc_szacunkowa - t.wartosc_szacunkowa) / NULLIF(b.wartosc_szacunkowa, 0) <= 0.02
WHERE b.czy_powyzej_progu_ue
  AND b.regon_zamawiajacy IS NOT NULL
  AND b.bzp_row_id NOT IN (SELECT bzp_row_id FROM core.v_matches_exact)
  AND b.bzp_row_id NOT IN (SELECT bzp_row_id FROM core.v_matches_fuzzy_nip)
  AND t.ted_row_id NOT IN (SELECT ted_row_id FROM core.v_matches_exact)
  AND t.ted_row_id NOT IN (SELECT ted_row_id FROM core.v_matches_fuzzy_nip);

CREATE OR REPLACE VIEW core.v_matches_fuzzy_regon AS
SELECT bzp_row_id, ted_row_id, 'fuzzy_heuristic_regon'::text AS match_method
FROM (
    SELECT *,
        ROW_NUMBER() OVER (PARTITION BY bzp_row_id ORDER BY combined_score) AS rn_bzp,
        ROW_NUMBER() OVER (PARTITION BY ted_row_id ORDER BY combined_score) AS rn_ted
    FROM core.v_matches_fuzzy_regon_candidates
) ranked
WHERE rn_bzp = 1 AND rn_ted = 1;

-- Suma obu warstw. match_method mowi, ktora warstwa znalazla dopasowanie -- audytowalne,
-- nie tylko "jakos sie dopasowalo".
CREATE OR REPLACE VIEW core.v_matches_fuzzy AS
SELECT bzp_row_id, ted_row_id, match_method FROM core.v_matches_fuzzy_nip
UNION ALL
SELECT bzp_row_id, ted_row_id, match_method FROM core.v_matches_fuzzy_regon;

-- Kandydaci w tolerancji (z ktorejkolwiek warstwy), ktorzy przegrali rywalizacje
-- o najlepsze dopasowanie po jednej ze stron. Nie znikaja po cichu -- ladują do
-- przegladu analitycznego.
CREATE OR REPLACE VIEW core.v_matches_needs_review AS
SELECT c.bzp_row_id, c.ted_row_id, c.dni_roznicy, c.pct_roznicy_wartosci, 'nip'::text AS warstwa
FROM core.v_matches_fuzzy_nip_candidates c
LEFT JOIN core.v_matches_fuzzy_nip f ON f.bzp_row_id = c.bzp_row_id AND f.ted_row_id = c.ted_row_id
WHERE f.bzp_row_id IS NULL
UNION ALL
SELECT c.bzp_row_id, c.ted_row_id, c.dni_roznicy, c.pct_roznicy_wartosci, 'regon'::text AS warstwa
FROM core.v_matches_fuzzy_regon_candidates c
LEFT JOIN core.v_matches_fuzzy_regon f ON f.bzp_row_id = c.bzp_row_id AND f.ted_row_id = c.ted_row_id
WHERE f.bzp_row_id IS NULL;

-- ============================================================
-- Widok finalny: BZP + TED polaczone, bez duplikatow, bez utraconych rekordow.
-- Przeliczany w calosci za kazdym razem (bezstanowo) -- tak pozniej przybyle
-- rekordy TED poprawnie doklejaja sie do starszych rekordow BZP.
-- ============================================================

CREATE OR REPLACE VIEW core.postepowania_polaczone AS
WITH dopasowania AS (
    SELECT bzp_row_id, ted_row_id, match_method FROM core.v_matches_exact
    UNION ALL
    SELECT bzp_row_id, ted_row_id, match_method FROM core.v_matches_fuzzy
),
bzp_bez_pary AS (
    SELECT bzp_row_id, NULL::bigint AS ted_row_id, 'bzp_only'::text AS match_method
    FROM staging.v_bzp_parsed
    WHERE bzp_row_id NOT IN (SELECT bzp_row_id FROM dopasowania)
),
ted_bez_pary AS (
    SELECT NULL::bigint AS bzp_row_id, ted_row_id, 'ted_only'::text AS match_method
    FROM staging.v_ted_parsed
    WHERE ted_row_id NOT IN (SELECT ted_row_id FROM dopasowania WHERE ted_row_id IS NOT NULL)
),
wszystkie AS (
    SELECT * FROM dopasowania
    UNION ALL SELECT * FROM bzp_bez_pary
    UNION ALL SELECT * FROM ted_bez_pary
)
SELECT
    w.match_method,
    b.bzp_notice_id,
    t.ted_notice_id,
    -- BZP = master dla tekstu (bogatszy opis PL), TED jako fallback gdy BZP nie istnieje
    COALESCE(b.payload->>'orderObject', t.payload->>'title')       AS tytul,
    -- TED = master dla slownikow (walidacja unijna), BZP jako fallback
    COALESCE(t.payload->>'cpv_code', b.payload->>'cpvCode') AS cpv_code,
    t.payload->>'nuts_code'                                   AS nuts_code,
    -- Kwoty: Architekt zatwierdzil trzymanie OBU wartosci + rozbieznosci zamiast
    -- wyboru jednej jako bazowej -- patrz POSEIDON_GUIDE.md. Wybor kwoty kanonicznej
    -- do liczenia premii nastapi w Fazie 4/5, na podstawie realnej skali rozbieznosci.
    b.wartosc_szacunkowa AS kwota_bzp,
    t.wartosc_szacunkowa AS kwota_ted,
    CASE WHEN b.wartosc_szacunkowa IS NOT NULL AND t.wartosc_szacunkowa IS NOT NULL
         THEN ABS(b.wartosc_szacunkowa - t.wartosc_szacunkowa) / NULLIF(b.wartosc_szacunkowa, 0)
    END AS rozbieznosc_kwot_pct
FROM wszystkie w
LEFT JOIN staging.v_bzp_parsed b ON b.bzp_row_id = w.bzp_row_id
LEFT JOIN staging.v_ted_parsed t ON t.ted_row_id = w.ted_row_id;

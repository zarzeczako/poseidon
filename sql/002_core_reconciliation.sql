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
    staging.clean_nip(payload->>'national_registration_number') AS nip_zamawiajacy,
    (payload->>'publication_date')::date                         AS data_publikacji,
    (payload->>'estimated_value')::numeric                       AS wartosc_szacunkowa,
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
-- ============================================================

CREATE OR REPLACE VIEW core.v_matches_fuzzy_candidates AS
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
  AND b.bzp_row_id NOT IN (SELECT bzp_row_id FROM core.v_matches_exact)
  AND t.ted_row_id NOT IN (SELECT ted_row_id FROM core.v_matches_exact);

CREATE OR REPLACE VIEW core.v_matches_fuzzy AS
SELECT bzp_row_id, ted_row_id, 'fuzzy_heuristic'::text AS match_method
FROM (
    SELECT *,
        ROW_NUMBER() OVER (PARTITION BY bzp_row_id ORDER BY combined_score) AS rn_bzp,
        ROW_NUMBER() OVER (PARTITION BY ted_row_id ORDER BY combined_score) AS rn_ted
    FROM core.v_matches_fuzzy_candidates
) ranked
WHERE rn_bzp = 1 AND rn_ted = 1;   -- wzajemnie najlepsze dopasowanie -> bezpieczne 1:1

-- Kandydaci w tolerancji, ktorzy przegrali rywalizacje o najlepsze dopasowanie
-- po jednej ze stron. Nie znikaja po cichu -- ladują do przegladu analitycznego.
CREATE OR REPLACE VIEW core.v_matches_needs_review AS
SELECT c.bzp_row_id, c.ted_row_id, c.dni_roznicy, c.pct_roznicy_wartosci
FROM core.v_matches_fuzzy_candidates c
LEFT JOIN core.v_matches_fuzzy f
    ON f.bzp_row_id = c.bzp_row_id AND f.ted_row_id = c.ted_row_id
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

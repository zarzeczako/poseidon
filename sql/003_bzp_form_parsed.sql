-- P.O.S.E.I.D.O.N. -- Faza 1: wyekstrahowane pola formularza BZP (SEKCJA I-VIII z htmlBody)
-- Ksztalt EAV (1 wiersz = 1 pole), celowo generyczny -- spojny z tym, jak surowy
-- payload jest trzymany jako JSONB, nie jako kolumna per pole API. Znaczenie
-- konkretnych kodow (ktory to "liczba ofert", ktory "cena") zyje w warstwie SQL
-- (widoki nizej), nie tutaj -- ta tabela tylko przechowuje to, co parser strukturalnie
-- wyciagnal z htmlBody (patrz etl/parse_bzp_form.py, POSEIDON_GUIDE.md).
--
-- W przeciwienstwie do staging.bzp_notices_raw/ted_notices_raw (append-only,
-- ON CONFLICT DO NOTHING -- surowa historia z API) ta tabela jest reprocesowalna:
-- ON CONFLICT DO UPDATE, bo to POCHODNE dane (wynik parsera), ktory moze zostac
-- poprawiony i ponownie puszczony nad juz zapisanym htmlBody bez ponownego
-- odpytywania API BZP.
--
-- Idempotentne (CREATE TABLE IF NOT EXISTS) w przeciwienstwie do 001_staging.sql --
-- wniosek z tego, ze 001 nim nie byl.

CREATE TABLE IF NOT EXISTS staging.bzp_form_parsed (
    id BIGSERIAL PRIMARY KEY,
    bzp_row_id BIGINT NOT NULL REFERENCES staging.bzp_notices_raw(id),
    czesc_nr INT,  -- NULL = pole na poziomie calej procedury (SEKCJA I-IV przed 1. czescia)
    code TEXT NOT NULL,  -- np. '6.1.)'
    etykieta TEXT,
    wartosc TEXT,  -- string jak w zrodle, celowo nietypowane -- patrz parse_bzp_form.py
    parsed_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    UNIQUE NULLS NOT DISTINCT (bzp_row_id, czesc_nr, code)
);

CREATE INDEX IF NOT EXISTS ix_bzp_form_parsed_row ON staging.bzp_form_parsed (bzp_row_id);

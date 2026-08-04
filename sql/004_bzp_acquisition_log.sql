-- P.O.S.E.I.D.O.N. -- Faza 1: checkpoint/resume dla etapowej pelnej akwizycji BZP.
-- Architekt wybral tempo "etapami" (np. rok po roku), nie jedna ciagla sesja -- ta
-- tabela pozwala bezpiecznie przerwac i wznowic fetch_bzp.py w trakcie zakresu dat
-- bez ponownego odpytywania API dla dni juz w calosci pobranych. Klucz to (day,
-- notice_type), nie sam day -- pozwala rozroznic czesciowy postep (np. ContractNotice
-- gotowe, TenderResultNotice jeszcze nie dla tego samego dnia).
--
-- Celowo NIE wnioskujemy ukonczenia z samej obecnosci wierszy w bzp_notices_raw --
-- dzien z 0 realnych ogloszen danego typu wygladalby identycznie jak dzien nigdy
-- nieprobowany, wiec potrzebny jest jawny marker "sprobowane i skonczone", nie tylko
-- "cos tu jest".

CREATE TABLE IF NOT EXISTS staging.bzp_acquisition_log (
    day DATE NOT NULL,
    notice_type TEXT NOT NULL,
    fetched_count INT NOT NULL,
    finished_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    PRIMARY KEY (day, notice_type)
);

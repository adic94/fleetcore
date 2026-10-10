-- Polityki RLS i uprawnienia dla KAŻDEJ tabeli z kolumną company_id.
-- Zasady: docs/10-database-design.md, rozdział „Polityki RLS".
--
-- Kontekst żądania ustawia warstwa połączenia API w każdej transakcji:
--   SET LOCAL app.company_ids = '3,7';   -- spółki z jawnych nadań (odczyt)
--   SET LOCAL app.company_id  = '3';     -- aktywna spółka (zapis)
--   SET LOCAL app.user_id     = '41';    -- dla polityk zależnych od flag nadania
-- current_setting bez drugiego argumentu: brak kontekstu = błąd, nie pusty wynik.

CREATE OR REPLACE FUNCTION core.ctx_company_ids() RETURNS BIGINT[]
  LANGUAGE sql STABLE AS
$$ SELECT string_to_array(current_setting('app.company_ids'), ',')::BIGINT[] $$;

CREATE OR REPLACE FUNCTION core.ctx_company_id() RETURNS BIGINT
  LANGUAGE sql STABLE AS
$$ SELECT current_setting('app.company_id')::BIGINT $$;

DO $$
DECLARE
  t record;
  -- tabele, w których company_id IS NULL oznacza wiersz wspólny (systemowy) widoczny dla wszystkich
  shared_rows text[] := ARRAY['core.dictionaries', 'integr.mappings'];
BEGIN
  FOR t IN
    SELECT c.oid, n.nspname AS s, c.relname AS r, format('%I.%I', n.nspname, c.relname) AS fq
    FROM pg_class c
    JOIN pg_namespace n ON n.oid = c.relnamespace
    JOIN pg_attribute a ON a.attrelid = c.oid AND a.attname = 'company_id' AND NOT a.attisdropped
    WHERE c.relkind IN ('r', 'p')                     -- tabele i tabele partycjonowane (bez partycji)
      AND NOT c.relispartition
      AND n.nspname IN ('core','docs','fleet','tax','fin','assets','telematics','rent','tms','integr','audit')
  LOOP
    EXECUTE format('ALTER TABLE %s ENABLE ROW LEVEL SECURITY', t.fq);
    EXECUTE format('ALTER TABLE %s FORCE ROW LEVEL SECURITY', t.fq);

    IF t.fq = ANY (shared_rows) THEN
      EXECUTE format($p$CREATE POLICY tenant_read ON %s FOR SELECT
        USING (company_id IS NULL OR company_id = ANY (core.ctx_company_ids()))$p$, t.fq);
    ELSE
      EXECUTE format($p$CREATE POLICY tenant_read ON %s FOR SELECT
        USING (company_id = ANY (core.ctx_company_ids()))$p$, t.fq);
    END IF;

    IF t.fq = 'audit.audit_logs' THEN
      -- audyt: tylko dopisywanie; odczyt przez tenant_read
      EXECUTE format($p$CREATE POLICY tenant_insert ON %s FOR INSERT
        WITH CHECK (company_id IS NULL OR company_id = core.ctx_company_id())$p$, t.fq);
      EXECUTE format('GRANT SELECT, INSERT ON %s TO fleetcore_app', t.fq);
    ELSE
      EXECUTE format($p$CREATE POLICY tenant_write ON %s FOR ALL
        USING (company_id = core.ctx_company_id())
        WITH CHECK (company_id = core.ctx_company_id())$p$, t.fq);
      -- uprawnienia tabela po tabeli — NIGDY „ON ALL TABLES IN SCHEMA" (otwiera widoki materializowane)
      EXECUTE format('GRANT SELECT, INSERT, UPDATE, DELETE ON %s TO fleetcore_app', t.fq);
    END IF;

    EXECUTE format('GRANT SELECT ON %s TO fleetcore_maint', t.fq);
  END LOOP;
END $$;

-- Spółki: użytkownik widzi tylko spółki ze swoich nadań; zakładanie spółek — wyłącznie funkcja superadmina.
ALTER TABLE core.companies ENABLE ROW LEVEL SECURITY;
ALTER TABLE core.companies FORCE ROW LEVEL SECURITY;
CREATE POLICY company_read ON core.companies FOR SELECT USING (id = ANY (core.ctx_company_ids()));
GRANT SELECT ON core.companies TO fleetcore_app;
GRANT SELECT, UPDATE ON core.companies TO fleetcore_maint;

-- Dane referencyjne bez company_id (gminy, uchwały, stawki): odczyt dla wszystkich, zapis tylko migracjami.
GRANT SELECT ON tax.municipalities, tax.rate_sets, tax.rates, tax.env_fee_rates TO fleetcore_app, fleetcore_maint;

-- Użytkownicy: aplikacja czyta konta, zapis przez funkcje administracyjne.
GRANT SELECT ON core.users TO fleetcore_app;

-- Trasy GPS: dodatkowa polityka RESTRYKCYJNA — odczyt pozycji tylko z flagą can_view_routes w nadaniu.
CREATE POLICY route_read ON telematics.positions AS RESTRICTIVE FOR SELECT
  USING (EXISTS (
    SELECT 1 FROM core.user_company_access uca
    WHERE uca.user_id = current_setting('app.user_id')::BIGINT
      AND uca.company_id = telematics.positions.company_id
      AND uca.can_view_routes
  ));

-- Nadania użytkownika czytane PRZED ustawieniem kontekstu (logowanie) — funkcja na roli bez RLS.
CREATE OR REPLACE FUNCTION core.user_companies(p_user_id BIGINT)
  RETURNS TABLE (company_id BIGINT, role TEXT, can_view_routes BOOLEAN, is_implementer BOOLEAN)
  LANGUAGE sql STABLE SECURITY DEFINER SET search_path = core, pg_temp AS
$$ SELECT company_id, role, can_view_routes, is_implementer
   FROM core.user_company_access WHERE user_id = p_user_id $$;
ALTER FUNCTION core.user_companies(BIGINT) OWNER TO fleetcore_maint;
REVOKE ALL ON FUNCTION core.user_companies(BIGINT) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION core.user_companies(BIGINT) TO fleetcore_app;

-- Status spółki: z 'active' nie ma powrotu do 'onboarding' (docs/14-onboarding-klienta.md).
CREATE OR REPLACE FUNCTION core.guard_company_lifecycle() RETURNS trigger LANGUAGE plpgsql AS $$
BEGIN
  IF OLD.lifecycle IN ('active','offboarding','closed') AND NEW.lifecycle = 'onboarding' THEN
    RAISE EXCEPTION 'company % cannot return from % to onboarding', OLD.id, OLD.lifecycle;
  END IF;
  RETURN NEW;
END $$;
CREATE TRIGGER trg_company_lifecycle BEFORE UPDATE OF lifecycle ON core.companies
  FOR EACH ROW EXECUTE FUNCTION core.guard_company_lifecycle();

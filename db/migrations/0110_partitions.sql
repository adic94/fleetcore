-- Partycje miesięczne dla tabel rosnących bez ograniczeń (docs/11, „Partycjonowanie").
-- Partycje tworzy zadanie cykliczne Z WYPRZEDZENIEM (kolejka `retention`/`partitions` w workerze),
-- a nie mechanizm reagujący na pierwszy nieudany zapis.

CREATE OR REPLACE FUNCTION core.ensure_month_partitions(p_months_back INT DEFAULT 1, p_months_ahead INT DEFAULT 3)
  RETURNS INT LANGUAGE plpgsql AS $$
DECLARE
  parent TEXT;
  m DATE;
  created INT := 0;
  part TEXT;
BEGIN
  FOREACH parent IN ARRAY ARRAY['fleet.events', 'telematics.positions', 'audit.audit_logs'] LOOP
    FOR i IN -p_months_back .. p_months_ahead LOOP
      m := (date_trunc('month', now()) + make_interval(months => i))::DATE;
      part := format('%s_%s', parent, to_char(m, 'YYYY_MM'));
      IF to_regclass(part) IS NULL THEN
        EXECUTE format('CREATE TABLE %s PARTITION OF %s FOR VALUES FROM (%L) TO (%L)',
                       part, parent, m, (m + INTERVAL '1 month')::DATE);
        created := created + 1;
      END IF;
    END LOOP;
  END LOOP;
  RETURN created;
END $$;

-- Na start: od miesiąca wstecz do trzech miesięcy naprzód. Dane historyczne z migracji floty
-- wymagają wcześniejszego wywołania z większym p_months_back.
SELECT core.ensure_month_partitions(1, 3);

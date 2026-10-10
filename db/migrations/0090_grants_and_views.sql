-- Wygenerowane z docs/10-database-design.md i docs/16-platforma-integracji.md (tools/gen-migrations-from-docs.py).
-- Uzasadnienia kolumn i ograniczeń: w dokumentacji. Po wygenerowaniu plik edytuje się ręcznie — NIE generuje się go ponownie.

REVOKE ALL ON SCHEMA public FROM PUBLIC;

GRANT USAGE ON SCHEMA core, fleet, tax, fin, rent, tms, assets, telematics, docs, integr, audit
  TO fleetcore_app, fleetcore_maint;

CREATE MATERIALIZED VIEW fleet.mv_vehicle_tco AS
SELECT company_id, vehicle_id,
       date_trunc('month', occurred_at)::DATE AS period,
       SUM(amount_net) FILTER (WHERE kind = 'refuel')               AS fuel_net,
       SUM(amount_net) FILTER (WHERE kind IN ('service','repair'))  AS service_net,
       SUM(amount_net) FILTER (WHERE kind = 'insurance')            AS insurance_net,
       SUM(amount_net) FILTER (WHERE kind = 'lease_payment')        AS lease_net,
       SUM(amount_net) FILTER (WHERE kind = 'toll')                 AS toll_net,
       SUM(amount_net)                                              AS total_net
FROM fleet.events
WHERE amount_net IS NOT NULL
GROUP BY 1, 2, 3;

CREATE UNIQUE INDEX ON fleet.mv_vehicle_tco (company_id, vehicle_id, period);

ALTER MATERIALIZED VIEW fleet.mv_vehicle_tco OWNER TO fleetcore_maint;

REVOKE ALL ON fleet.mv_vehicle_tco FROM PUBLIC, fleetcore_app;

CREATE VIEW fleet.v_vehicle_tco WITH (security_barrier) AS
SELECT * FROM fleet.mv_vehicle_tco
WHERE company_id = ANY (string_to_array(current_setting('app.company_ids'), ',')::BIGINT[]);

GRANT SELECT ON fleet.v_vehicle_tco TO fleetcore_app;

GRANT SELECT ON fleet.events TO fleetcore_maint;

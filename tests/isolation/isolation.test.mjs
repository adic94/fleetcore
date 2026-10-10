// Bramka `tenant-isolation` (docs/09-repository-structure.md, „Bramki testowe").
//
// Dwie części:
//  A. KATALOG — każda tabela z company_id ma włączone i wymuszone RLS; rola aplikacji nie ma
//     uprawnień do żadnego widoku materializowanego; rola aplikacji nie ma BYPASSRLS.
//  B. ZACHOWANIE — użytkownik spółki A nie czyta, nie zapisuje i nie wiąże rekordów spółki B.
//
// Uruchamiana na czystej bazie po `npm run db:migrate`. Wymaga DATABASE_URL (superuser/owner)
// i APP_DATABASE_URL (rola fleetcore_app).
import { test, before, after } from 'node:test';
import assert from 'node:assert/strict';
import pg from 'pg';

const admin = new pg.Client({ connectionString: process.env.DATABASE_URL });
const app = new pg.Client({ connectionString: process.env.APP_DATABASE_URL });
let A, B, vehA, vehB, branchB;

async function asApp(companyIds, activeCompany, fn, userId = 0) {
  await app.query('BEGIN');
  try {
    await app.query(`SELECT set_config('app.company_ids', $1, true), set_config('app.company_id', $2, true),
                            set_config('app.user_id', $3, true)`,
      [companyIds.join(','), String(activeCompany), String(userId)]);
    return await fn();
  } finally {
    await app.query('ROLLBACK');
  }
}

before(async () => {
  await admin.connect();
  await app.connect();
  const suffix = Date.now();
  A = (await admin.query(`INSERT INTO core.companies (code, name) VALUES ($1, 'Spółka A') RETURNING id`, [`a${suffix}`])).rows[0].id;
  B = (await admin.query(`INSERT INTO core.companies (code, name) VALUES ($1, 'Spółka B') RETURNING id`, [`b${suffix}`])).rows[0].id;
  branchB = (await admin.query(`INSERT INTO core.branches (company_id, code, name) VALUES ($1, 'B1', 'Oddział B') RETURNING id`, [B])).rows[0].id;
  vehA = (await admin.query(`INSERT INTO fleet.vehicles (company_id, plate) VALUES ($1, 'TEST-A') RETURNING id`, [A])).rows[0].id;
  vehB = (await admin.query(`INSERT INTO fleet.vehicles (company_id, plate) VALUES ($1, 'TEST-B') RETURNING id`, [B])).rows[0].id;
});

after(async () => {
  await app.end();
  await admin.end();
});

test('A1: każda tabela z company_id ma włączone i wymuszone RLS', async () => {
  const { rows } = await admin.query(`
    SELECT format('%I.%I', n.nspname, c.relname) AS t
    FROM pg_class c JOIN pg_namespace n ON n.oid = c.relnamespace
    JOIN pg_attribute a ON a.attrelid = c.oid AND a.attname = 'company_id' AND NOT a.attisdropped
    WHERE c.relkind IN ('r','p') AND NOT c.relispartition
      AND n.nspname NOT IN ('pg_catalog','information_schema','public')
      AND NOT (c.relrowsecurity AND c.relforcerowsecurity)`);
  assert.deepEqual(rows.map((r) => r.t), [], 'tabele bez RLS albo bez FORCE');
});

test('A2: rola aplikacji nie ma uprawnień do żadnego widoku materializowanego', async () => {
  const { rows } = await admin.query(`
    SELECT format('%I.%I', n.nspname, c.relname) AS mv
    FROM pg_class c JOIN pg_namespace n ON n.oid = c.relnamespace
    WHERE c.relkind = 'm' AND has_table_privilege('fleetcore_app', c.oid, 'SELECT')`);
  assert.deepEqual(rows.map((r) => r.mv), []);
});

test('A3: rola aplikacji nie ma BYPASSRLS ani SUPERUSER', async () => {
  const { rows } = await admin.query(`SELECT rolbypassrls, rolsuper FROM pg_roles WHERE rolname = 'fleetcore_app'`);
  assert.equal(rows[0].rolbypassrls, false);
  assert.equal(rows[0].rolsuper, false);
});

test('B1: bez kontekstu spółki zapytanie kończy się błędem, nie pustym wynikiem', async () => {
  await app.query('BEGIN');
  await assert.rejects(app.query('SELECT count(*) FROM fleet.vehicles'), /app\.company/);
  await app.query('ROLLBACK');
});

test('B2: użytkownik spółki A widzi tylko pojazdy spółki A', async () => {
  const ids = await asApp([A], A, async () => (await app.query('SELECT id FROM fleet.vehicles')).rows.map((r) => r.id));
  assert.ok(ids.includes(vehA));
  assert.ok(!ids.includes(vehB));
});

test('B3: pobranie pojedynczego rekordu spółki B po id zwraca zero wierszy (brak IDOR)', async () => {
  const n = await asApp([A], A, async () => (await app.query('SELECT 1 FROM fleet.vehicles WHERE id = $1', [vehB])).rowCount);
  assert.equal(n, 0);
});

test('B4: zapis rekordu do spółki B z kontekstu A jest odrzucany', async () => {
  await assert.rejects(
    asApp([A], A, () => app.query(`INSERT INTO fleet.vehicles (company_id, plate) VALUES ($1, 'X')`, [B])),
    /row-level security/,
  );
});

test('B5: aktualizacja i usunięcie rekordu spółki B z kontekstu A nie dotyka żadnego wiersza', async () => {
  const [u, d] = await asApp([A], A, async () => [
    (await app.query(`UPDATE fleet.vehicles SET brand = 'X' WHERE id = $1`, [vehB])).rowCount,
    (await app.query('DELETE FROM fleet.vehicles WHERE id = $1', [vehB])).rowCount,
  ]);
  assert.equal(u, 0);
  assert.equal(d, 0);
});

test('B6: rekord spółki A nie może wskazywać oddziału spółki B (klucz obcy z company_id)', async () => {
  await assert.rejects(
    admin.query('INSERT INTO fleet.vehicles (company_id, plate, branch_id) VALUES ($1, $2, $3)', [A, 'X', branchB]),
    /foreign key/,
  );
});

test('B7: operator z nadaniami A i B czyta obie spółki, ale zapisuje tylko w aktywnej', async () => {
  const ids = await asApp([A, B], A, async () => (await app.query('SELECT id FROM fleet.vehicles')).rows.map((r) => r.id));
  assert.ok(ids.includes(vehA) && ids.includes(vehB));
  await assert.rejects(
    asApp([A, B], A, () => app.query(`INSERT INTO fleet.vehicles (company_id, plate) VALUES ($1, 'X')`, [B])),
    /row-level security/,
  );
});

test('B8: widok TCO przez widok filtrujący pokazuje tylko spółki z kontekstu', async () => {
  await admin.query('REFRESH MATERIALIZED VIEW fleet.mv_vehicle_tco');
  const companies = await asApp([A], A, async () =>
    (await app.query('SELECT DISTINCT company_id FROM fleet.v_vehicle_tco')).rows.map((r) => Number(r.company_id)));
  assert.ok(companies.every((c) => c === Number(A)));
});

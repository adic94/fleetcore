#!/usr/bin/env node
// Dane syntetyczne do pracy lokalnej i do środowiska demo (przykładowa flota, docs/14).
// Wyłącznie zmyślone dane: VIN-y, tablice i nazwy nie odpowiadają żadnym realnym pojazdom.
// Użytkownik deweloperski: id zwracane na końcu — użyj go w nagłówku X-Dev-User.
import pg from 'pg';

const client = new pg.Client({ connectionString: process.env.DATABASE_URL });
await client.connect();
try {
  await client.query('BEGIN');
  const company = (await client.query(
    `INSERT INTO core.companies (code, name, lifecycle) VALUES ('demo', 'Flota Demo Sp. z o.o.', 'active')
     ON CONFLICT (code) DO UPDATE SET name = EXCLUDED.name RETURNING id`)).rows[0].id;

  const user = (await client.query(
    `INSERT INTO core.users (email, full_name) VALUES ('dev@fleetcore.local', 'Programista')
     ON CONFLICT (email) DO UPDATE SET full_name = EXCLUDED.full_name RETURNING id`)).rows[0].id;

  await client.query(
    `INSERT INTO core.user_company_access (user_id, company_id, role) VALUES ($1, $2, 'admin')
     ON CONFLICT (user_id, company_id) DO NOTHING`, [user, company]);

  const vehicles = [
    // plate,     kind,      dmc,   combo,  axles, susp
    ['DEMO001', 'passenger', 1900, null, 2, null],
    ['DEMO002', 'truck', 3500, null, 2, null],         // do 3,5 t — nie podlega DT-1
    ['DEMO003', 'truck', 7500, null, 2, null],         // 3,5–12 t — przedział DMC
    ['DEMO004', 'truck', 18000, null, 2, 'pneumatic'], // od 12 t — komplet
    ['DEMO005', 'truck', 26000, null, null, 'other'],  // od 12 t BEZ OSI — ma wyjść jako blokujący brak
    ['DEMO006', 'trailer', 24000, 40000, 3, 'pneumatic'],
    ['DEMO007', 'special', 16000, null, 2, null],      // specjalny — zwolniony
  ];
  for (const [plate, kind, dmc, combo, axles, susp] of vehicles) {
    await client.query(
      `INSERT INTO fleet.vehicles (company_id, vin, plate, kind, dmc_kg, combo_dmc_kg, axles_count, suspension_type)
       VALUES ($1, $2, $3, $4, $5, $6, $7, $8)
       ON CONFLICT DO NOTHING`,
      [company, `SYNTH${plate}000000`.slice(0, 17), plate, kind, dmc, combo, axles, susp]);
  }
  await client.query('COMMIT');
  console.log(`Seed OK. company_id=${company}, user_id=${user} (nagłówek X-Dev-User: ${user})`);
} catch (e) {
  await client.query('ROLLBACK');
  console.error(e.message);
  process.exitCode = 1;
} finally {
  await client.end();
}

#!/usr/bin/env node
// Uruchamia migracje z db/migrations/ w kolejności NUMERYCZNEJ, każdą w osobnej transakcji.
//
// Zasady z docs/08-cluster-deployment.md, „Migracje bazy":
//  1. pliki wycofujące (rollback/down) NIGDY nie są uruchamiane automatycznie — ich obecność to błąd;
//  2. sortowanie numeryczne, nie leksykograficzne;
//  3. błąd to błąd — nie ma statusu „już wykonane" dla nieudanego pliku;
//  4. plik już wykonany, którego treść się zmieniła, zatrzymuje migrację (migracji nie modyfikuje się po scaleniu).
//
// Użycie: DATABASE_URL=postgres://... node tools/migrate.mjs [--status]
import { createHash } from 'node:crypto';
import { readdirSync, readFileSync } from 'node:fs';
import { join, dirname } from 'node:path';
import { fileURLToPath } from 'node:url';
import pg from 'pg';

const DIR = join(dirname(fileURLToPath(import.meta.url)), '..', 'db', 'migrations');
const NAME = /^(\d{4})_[a-z0-9_]+\.sql$/;
const FORBIDDEN = /(rollback|down|revert|undo)/i;

function plan() {
  const files = readdirSync(DIR).filter((f) => f.endsWith('.sql'));
  const bad = files.filter((f) => FORBIDDEN.test(f) || !NAME.test(f));
  if (bad.length) {
    throw new Error(`Niedozwolone pliki w db/migrations (rollback albo zła nazwa): ${bad.join(', ')}`);
  }
  return files
    .map((f) => ({ file: f, seq: Number(f.match(NAME)[1]) }))
    .sort((a, b) => a.seq - b.seq)
    .map(({ file }) => {
      const sql = readFileSync(join(DIR, file), 'utf8');
      return { file, sql, sum: createHash('sha256').update(sql).digest('hex') };
    });
}

async function main() {
  const url = process.env.DATABASE_URL;
  if (!url) throw new Error('Brak DATABASE_URL');
  const client = new pg.Client({ connectionString: url });
  await client.connect();
  try {
    await client.query(`CREATE TABLE IF NOT EXISTS public.schema_migrations (
      file TEXT PRIMARY KEY, sha256 TEXT NOT NULL, applied_at TIMESTAMPTZ NOT NULL DEFAULT now())`);
    const { rows } = await client.query('SELECT file, sha256 FROM public.schema_migrations');
    const applied = new Map(rows.map((r) => [r.file, r.sha256]));

    for (const m of plan()) {
      if (applied.has(m.file)) {
        if (applied.get(m.file) !== m.sum) {
          throw new Error(`${m.file} został zmieniony po wykonaniu — dopisz nową migrację zamiast edytować starą`);
        }
        continue;
      }
      if (process.argv.includes('--status')) {
        console.log(`do wykonania: ${m.file}`);
        continue;
      }
      await client.query('BEGIN');
      try {
        await client.query(m.sql);
        await client.query('INSERT INTO public.schema_migrations (file, sha256) VALUES ($1, $2)', [m.file, m.sum]);
        await client.query('COMMIT');
        console.log(`OK  ${m.file}`);
      } catch (e) {
        await client.query('ROLLBACK');
        throw new Error(`BŁĄD ${m.file}: ${e.message}`);
      }
    }
  } finally {
    await client.end();
  }
}

main().catch((e) => {
  console.error(e.message);
  process.exit(1);
});

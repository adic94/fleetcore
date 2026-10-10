"""Jednorazowy generator: wyciąga SQL z docs/10 i docs/16, ustala kolejność wykonania
na czystym PostgreSQL 16 (kontener fc-pg-gen) i zapisuje numerowane migracje.

Uruchamiany raz przy tworzeniu szkieletu. Dalej migracje pisze się ręcznie w db/migrations/;
dokumentacja jest projektem, migracje są źródłem prawdy schematu.
"""
import io
import re
import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
DOCS = [ROOT / "docs" / "10-database-design.md", ROOT / "docs" / "16-platforma-integracji.md"]
OUT = ROOT / "db" / "migrations"
CONTAINER = sys.argv[1] if len(sys.argv) > 1 else "fc-pg-gen"

SCHEMAS = ["core", "docs", "fleet", "tax", "fin", "assets", "telematics", "rent", "tms", "integr", "audit"]

# Instrukcje z dokumentacji, które są przykładem, a nie schematem — w migracjach ich nie chcemy.
SKIP = [
    re.compile(r"^SET LOCAL", re.I),
    re.compile(r"^CREATE POLICY", re.I),                 # polityki generuje 0100_rls.sql dla wszystkich tabel
    re.compile(r"^ALTER TABLE fleet\.vehicles (ENABLE|FORCE)", re.I),
    re.compile(r"^CREATE ROLE", re.I),                   # role zakłada 0000_roles.sql idempotentnie
]


def statements():
    out = []
    for doc in DOCS:
        src = io.open(doc, encoding="utf-8").read()
        for block in re.findall(r"```sql\n(.*?)```", src, re.S):
            body = re.sub(r"--[^\n]*", "", block)
            for s in re.split(r";\s*\n", body):
                s = s.strip().rstrip(";").strip()
                if s and not any(p.search(s) for p in SKIP):
                    out.append(s)
    return out


def psql(sql):
    p = subprocess.run(
        ["docker", "exec", "-i", CONTAINER, "psql", "-U", "postgres", "-v", "ON_ERROR_STOP=1", "-q"],
        input=sql, capture_output=True, text=True, encoding="utf-8",
    )
    return p.returncode, (p.stderr or "").strip()


ROLES_SQL = """-- Role bazodanowe. Idempotentnie: na zarządzanym PostgreSQL role zakłada administrator,
-- a ten plik tylko je uzupełnia. Hasła ustawia się poza repozytorium (magazyn sekretów).
DO $$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'fleetcore_owner') THEN
    CREATE ROLE fleetcore_owner NOLOGIN;
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'fleetcore_migrator') THEN
    CREATE ROLE fleetcore_migrator LOGIN IN ROLE fleetcore_owner;
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'fleetcore_app') THEN
    CREATE ROLE fleetcore_app LOGIN NOBYPASSRLS NOSUPERUSER;
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'fleetcore_maint') THEN
    CREATE ROLE fleetcore_maint LOGIN BYPASSRLS NOSUPERUSER;
  END IF;
END $$;

CREATE SCHEMA IF NOT EXISTS core;
CREATE SCHEMA IF NOT EXISTS docs;
CREATE SCHEMA IF NOT EXISTS fleet;
CREATE SCHEMA IF NOT EXISTS tax;
CREATE SCHEMA IF NOT EXISTS fin;
CREATE SCHEMA IF NOT EXISTS assets;
CREATE SCHEMA IF NOT EXISTS telematics;
CREATE SCHEMA IF NOT EXISTS rent;
CREATE SCHEMA IF NOT EXISTS tms;
CREATE SCHEMA IF NOT EXISTS integr;
CREATE SCHEMA IF NOT EXISTS audit;
"""


def bucket(stmt):
    """Plik docelowy: grants/widoki na końcu, reszta wg pierwszego schematu w instrukcji."""
    head = stmt.split("(")[0]
    if re.match(r"^(GRANT|REVOKE)", stmt, re.I):
        return "0090_grants_and_views"
    if re.match(r"^(CREATE (MATERIALIZED )?VIEW|ALTER MATERIALIZED VIEW|CREATE UNIQUE INDEX ON fleet\.mv_)", stmt, re.I):
        return "0090_grants_and_views"
    if re.match(r"^CREATE EXTENSION", stmt, re.I):
        return "0001_extensions"
    for s in SCHEMAS:
        if re.search(rf"\b{s}\.", head):
            return {
                "core": "0010_core", "docs": "0020_docs", "fleet": "0030_fleet", "tax": "0040_tax",
                "fin": "0050_fin", "assets": "0060_assets_telematics", "telematics": "0060_assets_telematics",
                "rent": "0070_rent_tms", "tms": "0070_rent_tms", "integr": "0080_integr_audit",
                "audit": "0080_integr_audit",
            }[s]
    return "0090_grants_and_views"


def main():
    if any(OUT.glob("*.sql")) and "--force-overwrite" not in sys.argv:
        sys.exit("db/migrations zawiera już migracje — generator służył tylko do pierwszego wygenerowania. "
                 "Nowe zmiany schematu dopisuj jako nowe pliki migracji.")
    rc, err = psql(ROLES_SQL)
    if rc:
        sys.exit("roles: " + err)
    pending = statements()
    order, errors = [], {}
    while pending:
        nxt = []
        for s in pending:
            rc, err = psql(s + ";")
            if rc:
                nxt.append(s)
                errors[s] = err
            else:
                order.append(s)
        if len(nxt) == len(pending):
            for s in nxt:
                print("NIE PRZESZŁO:", s[:120].replace("\n", " "), "->", errors[s][:300])
            sys.exit(1)
        pending = nxt

    files = {}
    for s in order:
        files.setdefault(bucket(s), []).append(s)

    OUT.mkdir(parents=True, exist_ok=True)
    (OUT / "0000_roles_and_schemas.sql").write_text(ROLES_SQL, encoding="utf-8")
    header = ("-- Wygenerowane z docs/10-database-design.md i docs/16-platforma-integracji.md "
              "(tools/gen-migrations-from-docs.py).\n-- Uzasadnienia kolumn i ograniczeń: w dokumentacji. "
              "Po wygenerowaniu plik edytuje się ręcznie — NIE generuje się go ponownie.\n\n")
    for name in sorted(files):
        body = ";\n\n".join(files[name]) + ";\n"
        (OUT / f"{name}.sql").write_text(header + body, encoding="utf-8")
    print("instrukcji:", len(order), "plików:", len(files) + 1)


if __name__ == "__main__":
    main()

-- Role bazodanowe. Idempotentnie: na zarządzanym PostgreSQL role zakłada administrator,
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

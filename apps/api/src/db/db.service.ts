import { Injectable, OnModuleDestroy } from '@nestjs/common';
import { Pool, PoolClient } from 'pg';

/** Kontekst spółki wyliczony z core.user_company_access — NIGDY z parametru żądania. */
export interface TenantContext {
  userId: number;
  /** Spółki z jawnych nadań — odczyt. */
  companyIds: number[];
  /** Aktywna spółka — zapis. Musi należeć do companyIds. */
  activeCompanyId: number;
}

@Injectable()
export class DbService implements OnModuleDestroy {
  // Połączenie jako fleetcore_app: NOBYPASSRLS. Izolację wymusza baza, nie ten kod.
  private readonly pool = new Pool({ connectionString: process.env.APP_DATABASE_URL });

  /**
   * Jedyne miejsce, które ustawia zmienne app.* (docs/10, „Granica zaufania").
   * Każde zapytanie modułu domenowego idzie przez tę funkcję, w jednej transakcji z SET LOCAL.
   */
  async withTenant<T>(ctx: TenantContext, fn: (db: PoolClient) => Promise<T>): Promise<T> {
    if (!ctx.companyIds.includes(ctx.activeCompanyId)) {
      throw new Error('activeCompanyId spoza nadań użytkownika');
    }
    const client = await this.pool.connect();
    try {
      await client.query('BEGIN');
      await client.query(
        `SELECT set_config('app.company_ids', $1, true),
                set_config('app.company_id',  $2, true),
                set_config('app.user_id',     $3, true)`,
        [ctx.companyIds.join(','), String(ctx.activeCompanyId), String(ctx.userId)],
      );
      const result = await fn(client);
      await client.query('COMMIT');
      return result;
    } catch (e) {
      await client.query('ROLLBACK');
      throw e;
    } finally {
      client.release();
    }
  }

  /** Nadania użytkownika — czytane przed ustawieniem kontekstu, przez funkcję SECURITY DEFINER. */
  async userCompanies(userId: number): Promise<{ company_id: string; role: string }[]> {
    const { rows } = await this.pool.query('SELECT company_id, role FROM core.user_companies($1)', [userId]);
    return rows;
  }

  async ping(): Promise<boolean> {
    await this.pool.query('SELECT 1');
    return true;
  }

  async onModuleDestroy() {
    await this.pool.end();
  }
}

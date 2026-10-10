import { Controller, Get, NotFoundException, Param, ParseIntPipe, Req, UseGuards } from '@nestjs/common';
import type { Request } from 'express';
import { DbService, TenantContext } from '../../db/db.service';
import { TenantGuard } from '../../db/tenant.guard';

type TenantRequest = Request & { tenant: TenantContext };

// Każdy nowy punkt API ma wpis w tests/isolation w tym samym zgłoszeniu zmian (docs/09, „Konwencje").
@Controller('vehicles')
@UseGuards(TenantGuard)
export class VehiclesController {
  constructor(private readonly db: DbService) {}

  @Get()
  list(@Req() req: TenantRequest) {
    // Brak WHERE company_id — filtruje RLS w bazie. To celowe: zapomniany filtr nie jest tu możliwy.
    return this.db.withTenant(req.tenant, async (db) => {
      const { rows } = await db.query(
        `SELECT id, company_id, vin, plate, brand, model, kind, dmc_kg, axles_count, suspension_type, status
           FROM fleet.vehicles WHERE deleted_at IS NULL ORDER BY plate LIMIT 500`,
      );
      return rows;
    });
  }

  @Get(':id')
  async one(@Req() req: TenantRequest, @Param('id', ParseIntPipe) id: number) {
    const row = await this.db.withTenant(req.tenant, async (db) => {
      const { rows } = await db.query('SELECT * FROM fleet.vehicles WHERE id = $1 AND deleted_at IS NULL', [id]);
      return rows[0];
    });
    // Rekord cudzej spółki jest dla RLS niewidoczny — odpowiedź identyczna jak dla nieistniejącego.
    if (!row) throw new NotFoundException();
    return row;
  }
}

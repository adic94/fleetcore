import { Module } from '@nestjs/common';
import { DbModule } from './db/db.module';
import { HealthController } from './health/health.controller';
import { FleetModule } from './modules/fleet';

// Moduły domenowe (docs/09-repository-structure.md): core, fleet, rent, tms, fin, tax, assets,
// telematics, docs, integr. Moduł sięga do innego WYŁĄCZNIE przez jego index.ts albo zdarzenie.
@Module({
  imports: [DbModule, FleetModule],
  controllers: [HealthController],
})
export class AppModule {}

import { Global, Module } from '@nestjs/common';
import { DbService } from './db.service';
import { TenantGuard } from './tenant.guard';

@Global()
@Module({
  providers: [DbService, TenantGuard],
  exports: [DbService, TenantGuard],
})
export class DbModule {}

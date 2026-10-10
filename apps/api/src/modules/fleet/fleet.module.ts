import { Module } from '@nestjs/common';
import { VehiclesController } from './vehicles.controller';

@Module({
  controllers: [VehiclesController],
})
export class FleetModule {}

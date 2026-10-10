import 'reflect-metadata';
import { NestFactory } from '@nestjs/core';
import { AppModule } from './app.module';

async function bootstrap() {
  const app = await NestFactory.create(AppModule);
  app.setGlobalPrefix('v1');
  const port = Number(process.env.PORT ?? 3000);
  await app.listen(port);
  console.log(`FleetCore API: http://localhost:${port}/v1/health`);
}

void bootstrap();

import 'reflect-metadata';
import { NestFactory } from '@nestjs/core';
import { ConfigService } from '@nestjs/config';
import { ValidationPipe } from '@nestjs/common';
import { Request, Response, NextFunction } from 'express';
import { AppModule } from './app.module';
import { GlobalExceptionFilter } from './common/filters/global-exception.filter';
import { TransformInterceptor } from './common/interceptors/transform.interceptor';
import { validationExceptionFactory } from './common/pipes/validation-exception.factory';
import { ErrorLogsRepository } from './database/repositories/error-logs.repository';
import { RequestStatsRepository } from './database/repositories/request-stats.repository';
import { Config } from '@vitacare/shared-constants';

async function bootstrap() {
  const app = await NestFactory.create(AppModule);
  const configService = app.get(ConfigService);

  // admin-web (browser) and the API are always different origins — auth is
  // via Bearer token (not cookies), so no credentials/origin whitelist needed.
  app.enableCors();

  app.setGlobalPrefix(Config.API_VERSION_PREFIX);
  app.useGlobalPipes(
    new ValidationPipe({
      whitelist: true,
      forbidNonWhitelisted: true,
      transform: true,
      exceptionFactory: validationExceptionFactory,
    }),
  );
  app.useGlobalFilters(new GlobalExceptionFilter(app.get(ErrorLogsRepository)));
  app.useGlobalInterceptors(new TransformInterceptor());

  // Daily request/error counters for the admin-web "Error Logs" screen —
  // one UPSERT per request, fire-and-forget (never blocks the response).
  // Registered before the route handlers so it sees every request,
  // including ones that 404 before reaching a controller.
  const requestStatsRepo = app.get(RequestStatsRepository);
  app.use((req: Request, res: Response, next: NextFunction) => {
    res.on('finish', () => {
      requestStatsRepo.increment(res.statusCode >= 500).catch(() => {
        // Swallowed — a missed counter increment is never worth logging
        // noise over, let alone risking an unhandled rejection.
      });
    });
    next();
  });

  const port = configService.get<number>('API_PORT') ?? 3000;
  await app.listen(port);
}

bootstrap();

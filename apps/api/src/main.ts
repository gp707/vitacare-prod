import 'reflect-metadata';
import { NestFactory } from '@nestjs/core';
import { ConfigService } from '@nestjs/config';
import { ValidationPipe } from '@nestjs/common';
import { AppModule } from './app.module';
import { GlobalExceptionFilter } from './common/filters/global-exception.filter';
import { TransformInterceptor } from './common/interceptors/transform.interceptor';
import { validationExceptionFactory } from './common/pipes/validation-exception.factory';
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
  app.useGlobalFilters(new GlobalExceptionFilter());
  app.useGlobalInterceptors(new TransformInterceptor());

  const port = configService.get<number>('API_PORT') ?? 3000;
  await app.listen(port);
}

bootstrap();

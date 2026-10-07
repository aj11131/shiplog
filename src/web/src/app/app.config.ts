import { provideHttpClient, withInterceptors } from '@angular/common/http';
import {
  ApplicationConfig,
  ErrorHandler,
  inject,
  provideAppInitializer,
  provideBrowserGlobalErrorListeners,
} from '@angular/core';
import { provideRouter } from '@angular/router';
import { routes } from './app.routes';
import { APP_CONFIG, AppConfig } from './core/app-config';
import { authInterceptor } from './core/auth.interceptor';
import { AuthService } from './core/auth.service';
import { servedByInterceptor } from './core/served-by';
import { TelemetryErrorHandler, TelemetryService } from './core/telemetry.service';

export function createAppConfig(config: AppConfig): ApplicationConfig {
  return {
    providers: [
      provideBrowserGlobalErrorListeners(),
      provideRouter(routes),
      provideHttpClient(withInterceptors([authInterceptor, servedByInterceptor])),
      { provide: APP_CONFIG, useValue: config },
      { provide: ErrorHandler, useClass: TelemetryErrorHandler },
      // Awaited: a sign-in returning from Entra must complete before the first API call.
      provideAppInitializer(() => inject(AuthService).init()),
      // Not awaited: telemetry must never delay or block the app from starting.
      provideAppInitializer(() => void inject(TelemetryService).init()),
    ],
  };
}

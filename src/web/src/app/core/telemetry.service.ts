import { ErrorHandler, Injectable, inject } from '@angular/core';
import { NavigationEnd, Router } from '@angular/router';
import type { ApplicationInsights } from '@microsoft/applicationinsights-web';
import { filter } from 'rxjs';
import { APP_CONFIG } from './app-config';

/**
 * Browser telemetry via the Application Insights JavaScript SDK.
 *
 * It records page views, unhandled errors and AJAX calls, and adds W3C
 * `traceparent` headers to API requests. Because the API continues that trace, a
 * single click can be followed from the browser through the API to the database.
 *
 * It does nothing when no connection string is configured (e.g. local dev).
 */
@Injectable({ providedIn: 'root' })
export class TelemetryService {
  private readonly config = inject(APP_CONFIG);
  private readonly router = inject(Router);
  private appInsights?: ApplicationInsights;

  get enabled(): boolean {
    return this.appInsights !== undefined;
  }

  async init(): Promise<void> {
    if (!this.config.appInsightsConnectionString || this.appInsights) {
      return;
    }

    // Loaded on demand so the SDK (~180 kB) is only downloaded when telemetry is turned on.
    const { ApplicationInsights } = await import('@microsoft/applicationinsights-web');
    this.appInsights = new ApplicationInsights({
      config: {
        connectionString: this.config.appInsightsConnectionString,
        enableAutoRouteTracking: false, // page views are tracked from the Angular router below
        enableCorsCorrelation: true,
        enableRequestHeaderTracking: false,
        enableResponseHeaderTracking: false,
      },
    });
    this.appInsights.loadAppInsights();
    this.appInsights.addTelemetryInitializer((item) => {
      item.tags = { ...item.tags, 'ai.cloud.role': 'shiplog-web' };
      item.data = { ...item.data, environment: this.config.environment };
    });

    this.router.events
      .pipe(filter((e): e is NavigationEnd => e instanceof NavigationEnd))
      .subscribe((e) =>
        this.appInsights?.trackPageView({ name: e.urlAfterRedirects, uri: e.urlAfterRedirects }),
      );
  }

  trackException(error: unknown): void {
    this.appInsights?.trackException({
      exception: error instanceof Error ? error : new Error(String(error)),
    });
  }
}

/** Sends unhandled Angular errors to Application Insights as well as the console. */
@Injectable()
export class TelemetryErrorHandler implements ErrorHandler {
  private readonly telemetry = inject(TelemetryService);

  handleError(error: unknown): void {
    console.error(error);
    this.telemetry.trackException(error);
  }
}

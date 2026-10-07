import { InjectionToken } from '@angular/core';

/**
 * Settings that differ per environment (local, AKS, EKS).
 *
 * They are loaded at runtime from /config.json rather than compiled in, so the
 * same container image can be promoted between environments. In the container,
 * nginx renders config.json from environment variables when it starts; in
 * Kubernetes those come from the Helm chart.
 */
export interface AppConfig {
  /** Base URL of the API. Empty means "same origin" (nginx or the dev server proxies /api). */
  apiBaseUrl: string;
  /** Application Insights connection string. Empty disables browser telemetry. */
  appInsightsConnectionString: string;
  /** Display label, e.g. "local", "aks-dev". */
  environment: string;
  /** Entra ID sign-in. null = auth disabled (local dev, kind): anyone can write. */
  auth: AuthConfig | null;
}

export interface AuthConfig {
  /** The SPA's app registration (client) ID. */
  clientId: string;
  tenantId: string;
  /** The API permission to request, e.g. api://<api client id>/Entries.ReadWrite */
  apiScope: string;
}

export const APP_CONFIG = new InjectionToken<AppConfig>('APP_CONFIG');

export const defaultConfig: AppConfig = {
  apiBaseUrl: '',
  appInsightsConnectionString: '',
  environment: 'local',
  auth: null,
};

/** Fetches /config.json, falling back to defaults so the app still starts if it is missing. */
export async function loadConfig(fetchFn: typeof fetch = fetch): Promise<AppConfig> {
  try {
    const response = await fetchFn('/config.json', { cache: 'no-store' });
    if (!response.ok) {
      throw new Error(`HTTP ${response.status}`);
    }
    const loaded = { ...defaultConfig, ...((await response.json()) as Partial<AppConfig>) };
    // nginx always renders an "auth" object; empty IDs mean "disabled".
    const auth =
      loaded.auth?.clientId && loaded.auth.tenantId && loaded.auth.apiScope ? loaded.auth : null;
    return { ...loaded, auth };
  } catch (error) {
    console.warn('Could not load /config.json; using defaults.', error);
    return defaultConfig;
  }
}

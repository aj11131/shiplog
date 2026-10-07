import { Injectable, computed, inject, signal } from '@angular/core';
import type { AccountInfo, PublicClientApplication } from '@azure/msal-browser';
import { APP_CONFIG } from './app-config';

/** Where Entra sends the browser after sign-in: the MSAL v5 "redirect bridge" (see main.ts). */
export const REDIRECT_PATH = '/auth/redirect';

/**
 * Entra ID sign-in for the SPA, using MSAL Browser directly.
 *
 * The flow is OAuth 2.0 authorization code + PKCE: the browser is redirected to Entra, the
 * user signs in, and Entra redirects back with a one-time code that MSAL exchanges for
 * tokens. A SPA can't keep a secret, so PKCE (a per-login random proof) stands in for one.
 *
 * Tokens live in sessionStorage (cleared when the tab closes). MSAL's ~180 kB is
 * downloaded only when auth is configured.
 */
@Injectable({ providedIn: 'root' })
export class AuthService {
  private readonly config = inject(APP_CONFIG).auth;
  private msal?: PublicClientApplication;
  private msalModule?: typeof import('@azure/msal-browser');

  readonly enabled = this.config !== null;
  readonly account = signal<AccountInfo | null>(null);
  readonly signedIn = computed(() => this.account() !== null);
  readonly userName = computed(() => this.account()?.name ?? this.account()?.username ?? null);
  readonly error = signal<string | null>(null);

  /** Must finish before the app makes API calls: it completes a sign-in that is returning from Entra. */
  async init(): Promise<void> {
    if (!this.config) return;

    this.msalModule = await import('@azure/msal-browser');
    this.msal = new this.msalModule.PublicClientApplication({
      auth: {
        clientId: this.config.clientId,
        authority: `https://login.microsoftonline.com/${this.config.tenantId}`,
        redirectUri: window.location.origin + REDIRECT_PATH,
        postLogoutRedirectUri: window.location.origin + '/',
      },
      cache: { cacheLocation: 'sessionStorage' },
    });
    await this.msal.initialize();

    try {
      const result = await this.msal.handleRedirectPromise();
      if (result?.account) this.msal.setActiveAccount(result.account);
    } catch (err) {
      this.error.set(`Sign-in failed: ${(err as { errorCode?: string }).errorCode ?? err}`);
    }

    const account = this.msal.getActiveAccount() ?? this.msal.getAllAccounts()[0] ?? null;
    this.msal.setActiveAccount(account);
    this.account.set(account);
  }

  signIn(): Promise<void> {
    return this.requireMsal().loginRedirect({ scopes: [this.config!.apiScope] });
  }

  signOut(): Promise<void> {
    return this.requireMsal().logoutRedirect({ account: this.account() ?? undefined });
  }

  /**
   * An access token for the API, or null when signed out. MSAL serves it from cache or
   * silently refreshes it; only if Entra needs the user again (e.g. the session expired)
   * does it redirect to sign in.
   */
  async getAccessToken(): Promise<string | null> {
    const account = this.account();
    if (!this.msal || !account) return null;

    try {
      const result = await this.msal.acquireTokenSilent({
        scopes: [this.config!.apiScope],
        account,
      });
      return result.accessToken;
    } catch (err) {
      if (err instanceof this.msalModule!.InteractionRequiredAuthError) {
        await this.msal.acquireTokenRedirect({ scopes: [this.config!.apiScope], account });
      }
      throw err;
    }
  }

  private requireMsal(): PublicClientApplication {
    if (!this.msal) throw new Error('Sign-in is not configured.');
    return this.msal;
  }
}

import { TestBed } from '@angular/core/testing';
import { APP_CONFIG, AppConfig, defaultConfig } from './app-config';
import { AuthService, REDIRECT_PATH } from './auth.service';

// A fake MSAL module: the service loads @azure/msal-browser with a dynamic import, which
// vi.mock intercepts too.
const msal = vi.hoisted(() => {
  class InteractionRequiredAuthError extends Error {}
  const instance = {
    initialize: vi.fn(),
    handleRedirectPromise: vi.fn(),
    getActiveAccount: vi.fn(),
    getAllAccounts: vi.fn(),
    setActiveAccount: vi.fn(),
    loginRedirect: vi.fn(),
    logoutRedirect: vi.fn(),
    acquireTokenSilent: vi.fn(),
    acquireTokenRedirect: vi.fn(),
  };
  const PublicClientApplication = vi.fn(function () {
    return instance;
  });
  return { instance, PublicClientApplication, InteractionRequiredAuthError };
});
vi.mock('@azure/msal-browser', () => ({
  PublicClientApplication: msal.PublicClientApplication,
  InteractionRequiredAuthError: msal.InteractionRequiredAuthError,
}));

const authConfig: AppConfig = {
  ...defaultConfig,
  auth: { clientId: 'spa-id', tenantId: 'tenant-id', apiScope: 'api://api-id/Entries.ReadWrite' },
};
const alice = { name: 'Alice', username: 'alice@example.com', homeAccountId: 'h' };

function createService(config: AppConfig): AuthService {
  TestBed.configureTestingModule({ providers: [{ provide: APP_CONFIG, useValue: config }] });
  return TestBed.inject(AuthService);
}

describe('AuthService', () => {
  beforeEach(() => {
    vi.clearAllMocks();
    msal.instance.handleRedirectPromise.mockResolvedValue(null);
    msal.instance.getActiveAccount.mockReturnValue(null);
    msal.instance.getAllAccounts.mockReturnValue([]);
  });

  describe('when auth is not configured', () => {
    it('is disabled and never loads MSAL', async () => {
      const auth = createService(defaultConfig);

      await auth.init();

      expect(auth.enabled).toBe(false);
      expect(auth.signedIn()).toBe(false);
      expect(await auth.getAccessToken()).toBeNull();
      expect(msal.PublicClientApplication).not.toHaveBeenCalled();
    });
  });

  describe('when auth is configured', () => {
    it('configures MSAL for this tenant, with the redirect bridge as the redirect URI', async () => {
      const auth = createService(authConfig);

      await auth.init();

      expect(msal.PublicClientApplication).toHaveBeenCalledWith({
        auth: {
          clientId: 'spa-id',
          authority: 'https://login.microsoftonline.com/tenant-id',
          redirectUri: window.location.origin + REDIRECT_PATH,
          postLogoutRedirectUri: window.location.origin + '/',
        },
        cache: { cacheLocation: 'sessionStorage' },
      });
      expect(msal.instance.initialize).toHaveBeenCalled();
      expect(auth.signedIn()).toBe(false);
    });

    it('completes a sign-in that is returning from Entra', async () => {
      msal.instance.handleRedirectPromise.mockResolvedValue({ account: alice });
      msal.instance.getActiveAccount.mockReturnValue(alice);
      const auth = createService(authConfig);

      await auth.init();

      expect(msal.instance.setActiveAccount).toHaveBeenCalledWith(alice);
      expect(auth.signedIn()).toBe(true);
      expect(auth.userName()).toBe('Alice');
    });

    it('shows an error if the returning sign-in fails', async () => {
      msal.instance.handleRedirectPromise.mockRejectedValue({ errorCode: 'access_denied' });
      const auth = createService(authConfig);

      await auth.init();

      expect(auth.error()).toContain('access_denied');
      expect(auth.signedIn()).toBe(false);
    });

    it('signs in by redirecting, asking for the API scope', async () => {
      const auth = createService(authConfig);
      await auth.init();

      await auth.signIn();

      expect(msal.instance.loginRedirect).toHaveBeenCalledWith({
        scopes: ['api://api-id/Entries.ReadWrite'],
      });
    });

    it('gets access tokens silently', async () => {
      msal.instance.getAllAccounts.mockReturnValue([alice]);
      msal.instance.acquireTokenSilent.mockResolvedValue({ accessToken: 'token-123' });
      const auth = createService(authConfig);
      await auth.init();

      expect(await auth.getAccessToken()).toBe('token-123');
      expect(msal.instance.acquireTokenSilent).toHaveBeenCalledWith({
        scopes: ['api://api-id/Entries.ReadWrite'],
        account: alice,
      });
    });

    it('falls back to an interactive redirect when Entra needs the user again', async () => {
      msal.instance.getAllAccounts.mockReturnValue([alice]);
      msal.instance.acquireTokenSilent.mockRejectedValue(new msal.InteractionRequiredAuthError());
      const auth = createService(authConfig);
      await auth.init();

      await expect(auth.getAccessToken()).rejects.toBeInstanceOf(msal.InteractionRequiredAuthError);
      expect(msal.instance.acquireTokenRedirect).toHaveBeenCalled();
    });
  });
});

import { defaultConfig, loadConfig } from './app-config';

describe('loadConfig', () => {
  beforeEach(() => vi.spyOn(console, 'warn').mockImplementation(() => undefined));
  afterEach(() => vi.restoreAllMocks());

  it('merges /config.json over the defaults', async () => {
    const fetchFn = vi
      .fn()
      .mockResolvedValue(
        new Response(JSON.stringify({ environment: 'aks-dev', apiBaseUrl: 'https://api.example' })),
      );

    const config = await loadConfig(fetchFn);

    expect(fetchFn).toHaveBeenCalledWith('/config.json', { cache: 'no-store' });
    expect(config).toEqual({
      ...defaultConfig,
      environment: 'aks-dev',
      apiBaseUrl: 'https://api.example',
    });
  });

  it('falls back to defaults when the file is missing', async () => {
    const fetchFn = vi.fn().mockResolvedValue(new Response('not found', { status: 404 }));

    expect(await loadConfig(fetchFn)).toEqual(defaultConfig);
  });

  it('falls back to defaults when the request fails', async () => {
    const fetchFn = vi.fn().mockRejectedValue(new TypeError('network down'));

    expect(await loadConfig(fetchFn)).toEqual(defaultConfig);
  });

  it('enables auth only when all IDs are present', async () => {
    const auth = { clientId: 'spa', tenantId: 'tenant', apiScope: 'api://api/Entries.ReadWrite' };
    const respond = (a: unknown) =>
      vi.fn().mockResolvedValue(new Response(JSON.stringify({ auth: a })));

    expect((await loadConfig(respond(auth))).auth).toEqual(auth);
    expect(
      (await loadConfig(respond({ clientId: '', tenantId: '', apiScope: '' }))).auth,
    ).toBeNull();
    expect((await loadConfig(respond({ ...auth, apiScope: '' }))).auth).toBeNull();
  });
});

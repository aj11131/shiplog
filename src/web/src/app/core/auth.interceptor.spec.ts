import { HttpClient, provideHttpClient, withInterceptors } from '@angular/common/http';
import { HttpTestingController, provideHttpClientTesting } from '@angular/common/http/testing';
import { TestBed } from '@angular/core/testing';
import { fakeAuth } from '../testing/fixtures';
import { APP_CONFIG, defaultConfig } from './app-config';
import { authInterceptor } from './auth.interceptor';
import { AuthService } from './auth.service';

describe('authInterceptor', () => {
  let http: HttpClient;
  let httpMock: HttpTestingController;
  let auth: ReturnType<typeof fakeAuth>;

  beforeEach(() => {
    auth = fakeAuth({ enabled: true, signedInAs: 'Alice' });
    TestBed.configureTestingModule({
      providers: [
        provideHttpClient(withInterceptors([authInterceptor])),
        provideHttpClientTesting(),
        { provide: APP_CONFIG, useValue: defaultConfig },
        { provide: AuthService, useValue: auth },
      ],
    });
    http = TestBed.inject(HttpClient);
    httpMock = TestBed.inject(HttpTestingController);
  });

  afterEach(() => httpMock.verify());

  it('adds a bearer token to API calls when signed in', async () => {
    http.get('/api/entries').subscribe();
    await Promise.resolve(); // token lookup is async

    const req = httpMock.expectOne('/api/entries');
    expect(req.request.headers.get('Authorization')).toBe('Bearer test-token');
    req.flush([]);
  });

  it('never sends the token to anything that is not our API', async () => {
    http.get('https://telemetry.example.com/track').subscribe();
    await Promise.resolve();

    const req = httpMock.expectOne('https://telemetry.example.com/track');
    expect(req.request.headers.has('Authorization')).toBe(false);
    req.flush({});
  });

  it('sends API calls without a token when signed out', () => {
    auth.signInAs(null);

    http.get('/api/entries').subscribe();

    const req = httpMock.expectOne('/api/entries');
    expect(req.request.headers.has('Authorization')).toBe(false);
    expect(auth.getAccessToken).not.toHaveBeenCalled();
    req.flush([]);
  });
});
